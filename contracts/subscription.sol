pragma solidity ^0.5.3;

import "./math/SafeMath.sol";
import "./math/SafeMath64.sol";
import "./math/SafeMath8.sol";
import "./token/ERC20Token.sol";


interface CompoundContract {
  function  supply (address asset, uint256 amount) external returns (uint256);
  function withdraw (address asset, uint256 requestedAmount) external returns (uint256);
  function getSupplyBalance(address account, address asset) view external returns (uint);
}

/**
 * @title Compound Subscriptions in DAI
 */
contract Subscription {
    using SafeMath for uint256;
    using SafeMath64 for uint64;
    using SafeMath8 for uint8;

    uint128 internal constant ONE = 10 ** 18; // 10^18 is considered 1 in the price feed to allow for decimal calculations
    uint64 internal constant MAX_UINT64 = uint64(-1);
    uint256 internal constant MAX_ACCRUED_VALUE = 2**128;

    ERC20Token public dai;
    address public daiAddress;
    CompoundContract public compound;
    uint256 public totalBalances;
    uint256 constant base = 10 ** 18;
    uint256 constant percentBase = 100 * base;

    constructor(
        address _compoundAddress,
        address _daiAddress
    )
        public
    {
      dai = ERC20Token(_daiAddress);
      daiAddress = _daiAddress;
      compound = CompoundContract(_compoundAddress);
    }

    event AddAgreement(
        bytes32 agreementId,
        address indexed receiver,
        address indexed payor,
        address token,
        uint256 annualAmount,
        uint256 startDate,
        string indexed description
    );

    event SupplyReceived(
        address account,
        uint256 amount,
        uint256 startingBalance,
        uint256 newBalance,
        uint256 totalBalances
    );

    // Employees start at index 1, to allow us to use employees[0] to check for non-existent address
    // mappings with employeeIds
    uint256 public nextAgreement;

    struct Receiver {
      address accountAddress; // unique, but can be changed over time
      mapping(address => uint8) allocation;
    }

    struct Payor {
      address accountAddress;
      mapping(address => uint256) balances;
    }

    struct Agreement {
      address receiver;
      address payor;
      address token; // Token to be paid in
      uint256 payRate; // per second in denomination token
      uint256 accruedValue;
      uint256 lastPayment;
      uint256 endDate;
      string description;
      bool terminated;
    }

    mapping(address => uint256) public payorBalances;

    /**
      * @dev map: keccask256(...args) -> Agreement
      */
    mapping(bytes32 => Agreement) agreements;


    /**
     * @notice Do not pay directly into Subscription, please use `supply`.
     */
    function() payable external {
      revert();
    }

    // to get totalInterest subtract totalBalance from compound.supplyBalance
    // divide payRate by totalBalance for percentage
    // multiply percentage by totalInterest to get accumulated interest
    // userBalance = totalBalance + accumulatedInterest

    function percentOf(uint256 percent, uint256 target) internal pure returns (uint256) {
      return target * percent/percentBase;
    }

    function getAmountOwed(bytes32 agreementId) view public returns (uint256) {
      Agreement memory agreement = agreements[agreementId];
      //TODO check for enddate, use instead of now
      return (now.sub(agreement.lastPayment)).mul(agreement.payRate);
    }

    function withdrawFunds(bytes32 agreementId, uint256 amount) public {
      uint256 amountOwed = getAmountOwed(agreementId);
      if (amount == 0 || amountOwed == 0) return;
      require(amount <= amountOwed, "amount can not exceed amount owed");
      Agreement storage agreement = agreements[agreementId];
      uint256 payorBalance = payorBalances[agreement.payor];
      require(amount <= payorBalance, "amount can not exceed payor balance");

      // withdraw from savings to subscription contract
      compound.withdraw(daiAddress, amount);

      agreement.lastPayment = now;
      dai.transfer(msg.sender, amount);
      payorBalances[agreement.payor] = payorBalance.sub(amount);
      totalBalances = totalBalances.sub(amount);
      //emit MemberPaid( recipient,  amount, justification);
    }

    function supply(uint256 amount) public returns (uint256) {
      uint256 balance = payorBalances[msg.sender];
      dai.transferFrom(msg.sender, address(this), amount);
      compound.supply(daiAddress, amount);
      uint256 newBalance = balance.add(amount);
      payorBalances[msg.sender] = newBalance;
      totalBalances = totalBalances.add(amount);
      emit SupplyReceived(msg.sender, amount, balance, newBalance, totalBalances);
      return 0;
    }

    function createAgreement(
       address receiver,
       address payor,
       address token,
       uint256 annualAmount,
       uint256 startDate,
       string calldata description
    )
      external
    {
      require(msg.sender == payor, "Agreement must be created by payor");
      bytes32 agreementId = keccak256(abi.encode(receiver, payor, token, annualAmount, startDate, description));
      Agreement storage agreement = agreements[agreementId];

      agreement.receiver = receiver;
      agreement.payor = payor;
      agreement.token = token;
      agreement.payRate = annualAmount.div(365.25 days);
      agreement.lastPayment = startDate > 0 ? startDate : now;
      agreement.endDate = MAX_UINT64;
      agreement.description = description;

      emit AddAgreement(
          agreementId,
          receiver,
          payor,
          token,
          annualAmount,
          startDate > 0 ? startDate : now,
          description
     );

    }
}
