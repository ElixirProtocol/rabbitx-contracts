// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "forge-std/Test.sol";

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import {Distributor} from "src/Distributor.sol";

import {MockToken} from "test/utils/MockToken.sol";

contract TestDistributor is Test {
    /*//////////////////////////////////////////////////////////////
                                CONTRACTS
    //////////////////////////////////////////////////////////////*/

    MockToken public token;
    Distributor public rewards;

    /*//////////////////////////////////////////////////////////////
                                  USERS
    //////////////////////////////////////////////////////////////*/

    // Elixir signer
    address public signer;

    /*//////////////////////////////////////////////////////////////
                                  MISC
    //////////////////////////////////////////////////////////////*/

    // Random private key of signer.
    uint256 public privateKey = 0x12345;

    // EIP712 domain hash.
    bytes32 public eip712DomainHash;

    // cast keccak "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    bytes32 public constant TYPEHASH = 0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;

    // cast keccak "Claim(address user,address token,uint256 totalAmount)"
    bytes32 public constant CLAIM_TYPEHASH = 0xdf7cc1bcec129e9c71f8c092a98b5d1b22d01d1c64fb05a5f3ef1827b36466d2;

    struct Claim {
        address user;
        address token;
        uint256 totalAmount;
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // Set the signer.
        signer = vm.addr(privateKey);

        // Deploy token.
        token = new MockToken();

        // Deploy contract.
        rewards = new Distributor("Distributor", "1", signer);

        // Set the domain hash.
        eip712DomainHash = keccak256(
            abi.encode(
                TYPEHASH, keccak256(bytes("Distributor")), keccak256(bytes("1")), block.chainid, address(rewards)
            )
        );
    }

    // Computes the hash of a claim.
    function getStructHash(Claim memory _claim) internal pure returns (bytes32) {
        return keccak256(abi.encode(CLAIM_TYPEHASH, _claim.user, _claim.token, _claim.totalAmount));
    }

    // Computes the hash of the fully encoded EIP-712 message for the domain, which can be used to recover the signer
    function getTypedDataHash(Claim memory _claim) public view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", eip712DomainHash, getStructHash(_claim)));
    }

    function generateSignature(Claim memory claim) public returns (bytes memory signature) {
        bytes32 digest = getTypedDataHash(claim);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        signature = abi.encodePacked(r, s, v);

        assertEq(signature.length, 65);
    }

    /*//////////////////////////////////////////////////////////////
                                  TESTS
    //////////////////////////////////////////////////////////////*/

    function testDoubleClaim(uint256 amount) public {
        // Skip zeros.
        vm.assume(amount > 0 && amount <= type(uint128).max);

        // Mint tokens to contract.
        token.mint(address(rewards), amount);

        // Generate message to sign.
        Claim memory claim = Claim({user: address(this), token: address(token), totalAmount: amount});

        assertEq(token.balanceOf(address(rewards)), amount);

        rewards.claim(address(this), address(token), amount, generateSignature(claim));

        assertEq(token.balanceOf(address(rewards)), 0);

        // Generate anonther message to sign.
        Claim memory claim2 = Claim({user: address(this), token: address(token), totalAmount: amount * 2});

        // Mint tokens to contract.
        token.mint(address(rewards), amount);

        assertEq(token.balanceOf(address(rewards)), amount);

        rewards.claim(address(this), address(token), amount * 2, generateSignature(claim2));

        assertEq(token.balanceOf(address(rewards)), 0);
        assertEq(token.balanceOf(address(this)), amount * 2);
    }

    function testDoubleClaimNoFunds() public {
        uint256 amount = 100 ether;

        token.mint(address(rewards), amount);

        Claim memory claim = Claim({user: address(this), token: address(token), totalAmount: amount});

        bytes memory signature = generateSignature(claim);

        assertEq(token.balanceOf(address(rewards)), amount);

        rewards.claim(address(this), address(token), amount, signature);

        assertEq(token.balanceOf(address(rewards)), 0);

        rewards.claim(address(this), address(token), amount, signature);

        assertEq(token.balanceOf(address(rewards)), 0);
        assertEq(token.balanceOf(address(this)), amount);
    }

    function testInvalid() public {
        uint256 amount = 1 ether;

        vm.expectRevert(abi.encodeWithSelector(Distributor.InvalidToken.selector));
        rewards.claim(address(this), address(0), 0, bytes(""));

        vm.expectRevert(abi.encodeWithSelector(Distributor.InvalidAmount.selector));
        rewards.claim(address(this), address(token), 0, bytes(""));

        Claim memory claim = Claim({user: address(this), token: address(token), totalAmount: amount});

        bytes32 digest = getTypedDataHash(claim);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x123, digest);

        vm.expectRevert(abi.encodeWithSelector(Distributor.InvalidSignature.selector));
        rewards.claim(address(this), address(token), amount, abi.encodePacked(r, s, v));
    }

    function testNotUser() public {
        uint256 amount = 100 ether;

        token.mint(address(rewards), amount);

        Claim memory claim = Claim({user: address(0xbeef), token: address(token), totalAmount: amount});

        bytes memory signature = generateSignature(claim);

        assertEq(token.balanceOf(address(rewards)), amount);

        vm.expectRevert(abi.encodeWithSelector(Distributor.InvalidSignature.selector));
        rewards.claim(address(this), address(token), amount, signature);

        assertEq(token.balanceOf(address(rewards)), amount);
    }

    function testNotEnough() public {
        uint256 amount = 100 ether;

        Claim memory claim = Claim({user: address(this), token: address(token), totalAmount: amount});

        bytes memory signature = generateSignature(claim);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        rewards.claim(address(this), address(token), amount, signature);
    }

    function testWithdraw() public {
        uint256 amount = 100 ether;

        token.mint(address(rewards), amount);

        assertEq(token.balanceOf(address(rewards)), amount);

        rewards.emergencyWithdraw(address(token), amount);

        assertEq(token.balanceOf(address(rewards)), 0);
    }

    function testNotOwner() public {
        vm.prank(address(0xbeef));
        vm.expectRevert("Ownable: caller is not the owner");
        rewards.emergencyWithdraw(address(0), 0);
    }
}
