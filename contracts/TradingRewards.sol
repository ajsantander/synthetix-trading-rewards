pragma solidity ^0.5.17;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20Detailed.sol";
import "openzeppelin-solidity/contracts/token/ERC20/SafeERC20.sol";
import "openzeppelin-solidity/contracts/utils/ReentrancyGuard.sol";

import "./ITradingRewards.sol";


// TODO: Inherit RewardsDistributionRecipient, Pausable
contract TradingRewards is ITradingRewards, ReentrancyGuard {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    uint _currentPeriodID;
    mapping(uint => Period) _periods;

    struct Period {
        uint recordedFees;
        uint totalRewards;
        uint availableRewards;
        mapping(address => uint) recordedFeesForAccount;
        mapping(address => uint) claimedRewardsForAccount;
    }

    address _owner;
    address _rewardsDistribution;

    IERC20 _rewardsToken;

    /* ========== CONSTRUCTOR ========== */

    constructor(address owner, address rewardsToken, address rewardsDistribution) public {
        require(_validateAddress(owner), "Invalid owner account.");
        require(_validateAddress(rewardsToken), "Invalid rewards token.");
        require(_validateAddress(rewardsDistribution), "Invalid rewards distribution contract.");

        _owner = owner;
        _rewardsToken = IERC20(rewardsToken);
        _rewardsDistribution = rewardsDistribution;
    }

    function _validateAddress(address addr) internal pure returns (bool) {
        return addr != address(0);
    }

    /* ========== VIEWS ========== */

    function rewards(address account, uint periodID) external view returns (uint) {
        return _calculateAvailableRewardsForAccountInPeriod(account, periodID);
    }

    function rewardsForPeriods(address account, uint[] calldata periodIDs) external view returns (uint totalRewards) {
        for (uint i = 0; i < periodIDs.length; i++) {
            uint periodID = periodIDs[i];

            totalRewards = totalRewards.add(_calculateAvailableRewardsForAccountInPeriod(account, periodID));
        }
    }

    function _calculateAvailableRewardsForAccountInPeriod(address account, uint periodID) internal view returns (uint availableRewards) {
        Period storage period = _periods[periodID];

        if (period.availableRewards == 0) {
            return 0;
        }

        // TODO: Consider precision loss
        uint accountFees = period.recordedFeesForAccount[account];
        uint participationRatio = accountFees.div(period.recordedFees);
        uint maxRewards = participationRatio.mul(period.totalRewards);

        uint alreadyClaimed = period.claimedRewardsForAccount[account];
        availableRewards = maxRewards.sub(alreadyClaimed);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    // TODO: Implement onlyX modifier (onlyExchanger?)
    function recordExchangeFee(uint amount, address account) external {
        Period storage period = _periods[_currentPeriodID];

        period.recordedFeesForAccount[account] = period.recordedFeesForAccount[account].add(amount);
        period.recordedFees = period.recordedFees.add(amount);

        emit FeeRecorded(amount, account, _currentPeriodID);
    }

    function claimRewards(uint periodID) external nonReentrant {
        _claimRewards(msg.sender, periodID);
    }

    function claimRewardsForPeriods(uint[] calldata periodIDs) external nonReentrant {
        for (uint i = 0; i < periodIDs.length; i++) {
            uint periodID = periodIDs[i];

            _claimRewards(msg.sender, periodID);
        }
    }

    function _claimRewards(address account, uint periodID) internal {
        require(periodID < _currentPeriodID, "Cannot claim rewards on active period.");

        uint amountToClaim = _calculateAvailableRewardsForAccountInPeriod(account, periodID);

        Period storage period = _periods[periodID];
        period.claimedRewardsForAccount[account] = period.claimedRewardsForAccount[account].add(amountToClaim);
        period.availableRewards = period.availableRewards.sub(amountToClaim);

        _rewardsToken.safeTransfer(account, amountToClaim);

        emit RewardsClaimed(amountToClaim, account, _currentPeriodID);
    }

    // TODO: Use function from RewardsDistributionRecipient instead.
    function setRewardsDistribution(address newRewardsDistribution) external onlyOwner {
        require(_validateAddress(newRewardsDistribution), "Invalid rewards distribution contract.");

        _rewardsDistribution = newRewardsDistribution;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function notifyRewardAmount(uint newRewards) external onlyRewardsDistribution {
        uint currentBalance = _rewardsToken.balanceOf(address(this));
        uint targetBalance = currentBalance.add(newRewards);
        uint requiredAmount = targetBalance.sub(currentBalance);
        if (requiredAmount > 0) {
            _rewardsToken.safeTransferFrom(msg.sender, address(this), requiredAmount);
        }

        _currentPeriodID = _currentPeriodID.add(1);

        _periods[_currentPeriodID] = Period({
            totalRewards: newRewards,
            availableRewards: newRewards,
            recordedFees: 0
        });

        emit NewPeriodStarted(_currentPeriodID, newRewards);
    }

    function recoverTokens(address tokenAddress, uint amount) external onlyOwner {
        require(tokenAddress != address(_rewardsToken), "Reward tokens need to be withdrawn using another function.");

        IERC20(tokenAddress).safeTransfer(msg.sender, amount);

        emit TokensRecovered(tokenAddress, amount);
    }

    function withdrawRewardsTokensFromCurrentPeriod(uint amount) external onlyOwner {
        Period storage period = _periods[_currentPeriodID];

        require(period.availableRewards >= amount, "Unsufficient balance for required amount.");

        period.availableRewards = period.availableRewards.sub(amount);
        period.totalRewards = period.totalRewards.sub(amount);

        _rewardsToken.safeTransfer(msg.sender, amount);

        emit RewardsTokensWithdrawn(amount);
    }

    /* ========== MODIFIERS ========== */

    // TODO: Use modifier declared in RewardsDistributionRecipient instead.
    modifier onlyRewardsDistribution() {
        require(msg.sender == _rewardsDistribution, "Caller is not RewardsDistribution contract.");
        _;
    }

    // TODO: Use modifier declared in Owned instead.
    modifier onlyOwner() {
        require(msg.sender == _owner, "Caller is not owner.");
        _;
    }

    /* ========== EVENTS ========== */

    event FeeRecorded(uint amount, address account, uint periodID);
    event RewardsClaimed(uint amount, address account, uint periodID);
    event NewPeriodStarted(uint periodID, uint rewards);
    event TokensRecovered(address tokenAddress, uint amount);
    event RewardsTokensWithdrawn(uint amount);
}
