// SPDX-License-Identifier: UNLICENSED


pragma solidity ^0.8.21;

import "./openzeppelin/access/AccessControl.sol";
import "./openzeppelin/utils/Math.sol";
//import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/AccessControl.sol";
//import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/math/Math.sol";
import "./CallerContractInterface.sol";

contract EthPriceOracle is AccessControl {
    //using Roles for Roles.Role;
    using Math for uint256;
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
 
    uint private randNonce = 0;
    uint private modulus = 1000;
    uint private numOracles = 0;
    uint private THRESHOLD = 0;

    mapping(uint256 => bool) pendingRequests;
    mapping(uint256 => Response[]) requestIdToResponse;

    struct Response {
        address oracleAddress;
        address callerAddress;
        uint256 ethPrice;
    }

    event GetLatestEthPriceEvent(address callerAddress, uint id);
    event SetLatestEthPriceEvent(uint256 ethPrice, address callerAddress);
    event AddOracleEvent(address oracleAddress);
    event RemoveOracleEvent(address oracleAddress);
    event SetThresholdEvent(uint threshold);

    constructor(address _owner)  {
            _grantRole(OWNER_ROLE, _owner);
    }

    function addOracle(address _oracle) public {
        require(hasRole(OWNER_ROLE,msg.sender), "Not an owner!");
        require(!hasRole(ORACLE_ROLE,_oracle), "Already an oracle!");
        grantRole(ORACLE_ROLE, _oracle);
        numOracles++;
        emit AddOracleEvent(_oracle);
    }

    function removeOracle(address _oracle) public {
        require(hasRole(OWNER_ROLE,msg.sender), "Not an owner!");
        require(hasRole(ORACLE_ROLE,_oracle), "Not an oracle!");
        require(numOracles > 1, "Do not remove the last oracle!");
        revokeRole(ORACLE_ROLE, _oracle);
        numOracles--;
        emit RemoveOracleEvent(_oracle);
    }

    function setThreshold(uint _threshold) public {
        require(hasRole(OWNER_ROLE,msg.sender), "Not an owner!");
        THRESHOLD = _threshold;
        emit SetThresholdEvent(THRESHOLD);
    }

    /// @notice Computes and generates the request id and, for security reasons, this number should be hard to guess. Generating a unique id makes it harder for oracles to collude and manipulate the price for a particular request.
    /// @dev Uses a naive random number generataion algorithm, better to use Chainlink VRF
    /// @return The request ID, a random number between 0 and modulus
    function getLatestEthPrice() public returns (uint256) {
        randNonce++;
        uint id = uint( keccak256(abi.encodePacked(block.timestamp, msg.sender, randNonce))   ) % modulus;
        pendingRequests[id] = true;
        emit GetLatestEthPriceEvent(msg.sender, id);
        return id;
    }

    function setLatestEthPrice(
        uint256 _ethPrice,
        address _callerAddress,
        uint256 _id
    ) public {
        require(hasRole(ORACLE_ROLE,msg.sender), "Not an oracle!");
        require(
            pendingRequests[_id],
            "This request is not in my pending list."
        );
        // Create a response and add it to the request id
        Response memory resp;
        resp = Response(msg.sender, _callerAddress, _ethPrice);
        requestIdToResponse[_id].push(resp);
        uint numResponses = requestIdToResponse[_id].length;
        // If oracle responses reaches threshold, calculate the median ETH price and fulfill the request
        if (numResponses == THRESHOLD) {
            uint computedEthPrice = 0;
            for (uint f = 0; f < requestIdToResponse[_id].length; f++) {
                computedEthPrice = computedEthPrice += requestIdToResponse[_id][f].ethPrice;
            }
            computedEthPrice = computedEthPrice / numResponses;
            delete pendingRequests[_id];
            delete requestIdToResponse[_id];
            CallerContractInterface callerContractInstance;
            callerContractInstance = CallerContractInterface(_callerAddress);
            callerContractInstance.callback(computedEthPrice, _id);
            emit SetLatestEthPriceEvent(computedEthPrice, _callerAddress);
        }
    }
}
