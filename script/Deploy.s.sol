// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../contracts/utils/DummyProofVerifier.sol";
import "../contracts/utils/DummyLightClient.sol";
import "../contracts/core/Dispatcher.sol";
import {Mars} from "../contracts/examples/Mars.sol";
import {IDispatcher} from "../contracts/core/Dispatcher.sol";
import {IUniversalChannelHandler} from "../contracts/interfaces/IUniversalChannelHandler.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../contracts/core/OpProofVerifier.sol";
import "../contracts/core/OpLightClient.sol";
import "../contracts/core/UniversalChannelHandler.sol";
import "../contracts/examples/Earth.sol";

contract Deploy is Script {
    using stdJson for string;

    modifier broadcast() {
        vm.startBroadcast(msg.sender);
        _;
        vm.stopBroadcast();
    }

    function _implSalt() internal returns (bytes32) {
        return keccak256(bytes(vm.envOr("IMPL_SALT", string("polymer"))));
    }

    function run() public {
        string memory chain = vm.envString("CHAIN");
        string memory portPrefix = vm.envOr("PORT_PREFIX", string("polyibc."));
        portPrefix = string.concat(portPrefix, chain, ".");

        console.log("Deploying dummy contracts to %s...", chain);

        address stateManager = deployDummyLightClient();
        address dispatcher = deployDispatcher(portPrefix, stateManager);
        deployMars(dispatcher);

        address universalChannelHandler = deployUniversalChannelHandler(dispatcher);
        deployEarth(universalChannelHandler);

        console.log("\nDeploying contracts with proofs to %s...", chain);
        address l2OutputOracleAddress = vm.envAddress("L2_OUTPUT_ORACLE_ADDRESS");
        address proofVerifierAddr = deployOpProofVerifier(l2OutputOracleAddress);

        address l1BlockProvider = vm.envOr("L1_BLOCK_PROVIDER", 0x4200000000000000000000000000000000000015);
        uint32 fraudProofWindowSecs = 0;
        address opStateManager = deployOpLightClient(fraudProofWindowSecs, proofVerifierAddr, l1BlockProvider);

        dispatcher = deployDispatcher(portPrefix, opStateManager);
        deployMars(dispatcher);

        universalChannelHandler = deployUniversalChannelHandler(dispatcher);
        deployEarth(universalChannelHandler);
    }

    function deployDummyLightClient() public broadcast returns (address addr_) {
        DummyLightClient manager = new DummyLightClient{salt: _implSalt()}();
        console.log("DummyLightClient deployed at %s", address(manager));
        return address(manager);
    }

    function deployDispatcher(string memory portPrefix, address stateManager_)
        public
        broadcast
        returns (address addr_)
    {
        Dispatcher impl = new Dispatcher{salt: _implSalt()}();
        IDispatcher proxy = IDispatcher(
            address(
                new ERC1967Proxy{salt: _implSalt()}(
                    address(impl),
                    abi.encodeWithSelector(Dispatcher.initialize.selector, portPrefix, DummyLightClient(stateManager_))
                )
            )
        );

        console.log("Dispatcher imnplementation at %s", address(impl));
        console.log("Dispatcher proxy at %s", address(proxy));
        return address(proxy);
    }

    function deployMars(address dispatcher) public broadcast returns (address addr_) {
        Mars mars = new Mars{salt: _implSalt()}(IbcDispatcher(dispatcher));
        console.log("Mars deployed at %s", address(mars));
        return address(mars);
    }

    function deployOpProofVerifier(address l2OutputOracleAddress) public broadcast returns (address addr_) {
        OpProofVerifier verifier = new OpProofVerifier{salt: _implSalt()}(l2OutputOracleAddress);
        console.log("OpProofVerifier deployed at %s", address(verifier));
        return address(verifier);
    }

    function deployOpLightClient(uint32 fraudProofWindowSecs, address proofVerifierAddr, address l1BlockProvider)
        public
        broadcast
        returns (address addr_)
    {
        OptimisticLightClient manager = new OptimisticLightClient{salt: _implSalt()}(
            fraudProofWindowSecs, ProofVerifier(proofVerifierAddr), L1Block(l1BlockProvider)
        );
        console.log("OptimisticLightClient deployed at %s", address(manager));
        return address(manager);
    }

    function deployUniversalChannelHandler(address dispatcher) public broadcast returns (address addr_) {
        UniversalChannelHandler uchImplementation = new UniversalChannelHandler();
        IUniversalChannelHandler proxy = IUniversalChannelHandler(
            address(
                new ERC1967Proxy(
                    address(uchImplementation),
                    abi.encodeWithSelector(UniversalChannelHandler.initialize.selector, dispatcher)
                )
            )
        );
        console.log("UniversalChannelHandler implementation deployed at %s", address(uchImplementation));
        console.log("UniversalChannelHandler proxy deployed at %s", address(proxy));
        return address(proxy);
    }

    function deployEarth(address middleware) public broadcast returns (address addr_) {
        Earth earth = new Earth{salt: _implSalt()}(middleware);
        console.log("Earth deployed at %s", address(earth));
        return address(earth);
    }
}
