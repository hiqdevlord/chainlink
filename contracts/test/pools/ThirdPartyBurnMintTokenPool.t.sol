// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IBurnMintERC20} from "../../interfaces/pools/IBurnMintERC20.sol";

import "../BaseTest.t.sol";
import {ThirdPartyBurnMintTokenPool} from "../../pools/ThirdPartyBurnMintTokenPool.sol";
import {TokenPool} from "../../pools/TokenPool.sol";
import {Router} from "../../Router.sol";
import {BurnMintERC677} from "../../pools/tokens/BurnMintERC677.sol";

contract ThirdPartyBurnMintTokenPoolSetup is BaseTest {
  IERC20 internal s_token;
  ThirdPartyBurnMintTokenPool internal s_thirdPartyPool;
  address internal s_routerAllowedOffRamp = address(234);
  Router internal s_router;

  function setUp() public virtual override {
    BaseTest.setUp();
    s_token = new BurnMintERC677("LINK", "LNK", 18);
    deal(address(s_token), OWNER, type(uint256).max);

    s_router = new Router(address(s_token));

    Router.OnRamp[] memory onRampUpdates = new Router.OnRamp[](0);
    Router.OffRamp[] memory offRampUpdates = new Router.OffRamp[](1);
    address[] memory offRamps = new address[](1);
    offRamps[0] = s_routerAllowedOffRamp;
    offRampUpdates[0] = Router.OffRamp({sourceChainSelector: SOURCE_CHAIN_ID, offRamp: s_routerAllowedOffRamp});

    s_router.applyRampUpdates(onRampUpdates, new Router.OffRamp[](0), offRampUpdates);

    s_thirdPartyPool = new ThirdPartyBurnMintTokenPool(
      IBurnMintERC20(address(s_token)),
      rateLimiterConfig(),
      address(s_router)
    );
    BurnMintERC677(address(s_token)).grantMintAndBurnRoles(address(s_thirdPartyPool));
  }
}

contract ThirdPartyBurnMintTokenPool_applyRampUpdates is ThirdPartyBurnMintTokenPoolSetup {
  event OnRampAllowanceSet(address onRamp, bool allowed);
  event OffRampAllowanceSet(address onRamp, bool allowed);

  function testApplyRampUpdatesSuccess() public {
    TokenPool.RampUpdate[] memory onRamps = new TokenPool.RampUpdate[](1);
    onRamps[0] = TokenPool.RampUpdate({ramp: address(1), allowed: true});

    TokenPool.RampUpdate[] memory offRamps = new TokenPool.RampUpdate[](1);
    offRamps[0] = TokenPool.RampUpdate({ramp: s_routerAllowedOffRamp, allowed: true});

    vm.expectEmit();
    emit OnRampAllowanceSet(onRamps[0].ramp, true);

    vm.expectEmit();
    emit OffRampAllowanceSet(offRamps[0].ramp, true);

    s_thirdPartyPool.applyRampUpdates(onRamps, offRamps);

    offRamps[0] = TokenPool.RampUpdate({ramp: s_routerAllowedOffRamp, allowed: false});

    vm.expectEmit();
    emit OffRampAllowanceSet(offRamps[0].ramp, false);

    s_thirdPartyPool.applyRampUpdates(onRamps, offRamps);
  }

  // Reverts

  function testInvalidOffRampReverts() public {
    address invalidOffRamp = address(23456787654321);
    TokenPool.RampUpdate[] memory offRamps = new TokenPool.RampUpdate[](1);
    offRamps[0] = TokenPool.RampUpdate({ramp: invalidOffRamp, allowed: true});

    vm.expectRevert(abi.encodeWithSelector(ThirdPartyBurnMintTokenPool.InvalidOffRamp.selector, invalidOffRamp));

    s_thirdPartyPool.applyRampUpdates(new TokenPool.RampUpdate[](0), offRamps);
  }
}
