/**
 *Submitted for verification at BscScan.com on 2021-07-27
*/

// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;


interface IERC20 {
    function totalSupply() external view returns (uint);
    function balanceOf(address account) external view returns (uint);
    function transfer(address recipient, uint amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint);
    function approve(address spender, uint amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint amount) external returns (bool);
    function burn(address account, uint amount) external; // here it is
    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);
    event Burn(address indexed account, uint amount);
}

library SafeERC20 {
    using SafeMath for uint;
    using Address for address;

    function safeTransfer(IERC20 token, address to, uint value) internal {
        callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint value) internal {
        callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    function safeApprove(IERC20 token, address spender, uint value) internal {
        require((value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }
    function callOptionalReturn(IERC20 token, bytes memory data) private {
        require(address(token).isContract(), "SafeERC20: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "SafeERC20: low-level call failed");

        if (returndata.length > 0) { // Return data is optional
            // solhint-disable-next-line max-line-length
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

library SafeMath {
    function add(uint a, uint b) internal pure returns (uint) {
        uint c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }
    function sub(uint a, uint b) internal pure returns (uint) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }
    function sub(uint a, uint b, string memory errorMessage) internal pure returns (uint) {
        require(b <= a, errorMessage);
        uint c = a - b;

        return c;
    }
    function mul(uint a, uint b) internal pure returns (uint) {
        if (a == 0) {
            return 0;
        }

        uint c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }
    function div(uint a, uint b) internal pure returns (uint) {
        return div(a, b, "SafeMath: division by zero");
    }
    function div(uint a, uint b, string memory errorMessage) internal pure returns (uint) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0, errorMessage);
        uint c = a / b;

        return c;
    }
}

library Address {
    function isContract(address account) internal view returns (bool) {
        bytes32 codehash;
        bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
        // solhint-disable-next-line no-inline-assembly
        assembly { codehash := extcodehash(account) }
        return (codehash != 0x0 && codehash != accountHash);
    }
}  

interface Iflash{
    function rate() external view returns(uint u, uint token);
}
/*
 * this contract is valut implementation, users stake Torch to redeem LPs
*/ 
contract LpVault{
    
    address public Torch;
    address public pancakePair; // Torch-USDT lp address
    address public flashExchange;

    address public owner;
    uint public init_time;    // initial time for stake
    uint public init_time_lp; // initial time for LP mining 
    
    bool public initiated;

    uint public periodFinish; 

    uint[5] public periods = [7 days, 30 days, 100 days, 200 days, 300 days]; // 7 30 100 200 300 days
    
    function _msgSender() internal view returns(address){
        return msg.sender;
    }
    
    
    uint public LP_total; // LP rewards released

    mapping(uint=>PoolInfo) public poolInfo;
    mapping(address => UserStake) userStake;
    mapping(address => UserAccount) userAccount;
    
    mapping(address => bool) public Blacklist;
    
    struct PoolInfo{
        uint amount;
        uint participants;
        uint yieldRate;
        uint yieldAmount;
    }
    
    struct UserStake{
        uint[5] stake_amounts;
        uint[5] stake_rewards;
        uint[5] timestamps;
        
        uint stake_total; // total staken Torch quantity
        
    }
    
    struct UserAccount{
        address invitor;
        uint depositTimes;
        uint LP_n; // lp available
        uint level;
        uint refer_n; // number of people you invited
    }
    
    event Stake(address indexed _user, uint _poolId, uint indexed _amount, uint indexed lpRewards);
    event Unstake(address indexed _user, uint indexed _poolId, uint indexed _amount);
    event BondRefer(address indexed _user, address indexed _invitor);
    
    
// -------------------------------------------Owner methods-----------------------------------------------------
    modifier onlyOwner{
        require(_msgSender() == owner, "Not permitted!!!");
        _;
    }
    
    modifier notBlack{
        require(!Blacklist[_msgSender()], "you are on blacklist");
        _;
    }
    
    function transferOwnership(address _newOwner)public onlyOwner{
        owner = _newOwner; 
    }
    
    
    constructor(){
        owner = _msgSender();
        
        // initialize stake pool info
        poolInfo[1] = PoolInfo(0,0,1,0);
        poolInfo[2] = PoolInfo(0,0,2,0);
        poolInfo[3] = PoolInfo(0,0,3,0);
        poolInfo[4] = PoolInfo(0,0,4,0);
        poolInfo[5] = PoolInfo(0,0,6,0);
        
        
    }
    
    function setTorch(address _token)public onlyOwner{
        Torch = _token;
    } 
    
    // set lock_periods
    function setPeriods(uint[5] memory _periods) public onlyOwner{
        periods[0] = _periods[0];
        periods[1] = _periods[1];
        periods[2] = _periods[2];
        periods[3] = _periods[3];
        periods[4] = _periods[4];
        
    }
    
    
   
    
    
    
// -------------------------------------------User methods-----------------------------------------------------
    
    // user stakes Torch
    function stake(uint poolId, uint amount, address _invitor) external virtual notBlack{
        require(initiated,"not initiated yet");
        require(poolId >= 1 && poolId <= 5, "wrong pool id");
        
        // keep the integer part
        uint _amount = amount - amount % 1e18;
        require(_amount >= 1e18, "at leaset 1 unit");
        
        // for the first time user, invitor should be the community or another senior user 
        if(userAccount[_msgSender()].invitor == address(0)){
            require(userAccount[_invitor].invitor != address(0) || _invitor == address(this), "illegal invitor");
            userAccount[_msgSender()].invitor = _invitor;
            
            // bond referral relation
            emit BondRefer(msg.sender, _invitor);
            
            address temp_user = userAccount[_msgSender()].invitor;
            for(uint i= 0;i<20;i++){
                if(temp_user== address(0) || temp_user == address(this)){break;}
                else{
                    userAccount[temp_user].refer_n += 1;
                    temp_user = userAccount[temp_user].invitor;
                    }
                }
        }
        
        require(IERC20(Torch).transferFrom(_msgSender(), address(this), _amount), "transfer failed");
        // update user stake records
        userStake[_msgSender()].stake_amounts[poolId-1] += _amount;
        userStake[_msgSender()].timestamps[poolId-1] = block.timestamp;
        userStake[_msgSender()].stake_total += _amount;
        
        uint LP_rewards = _amount * poolInfo[poolId].yieldRate * getTorchPrice() / 1 ether;
        userStake[_msgSender()].stake_rewards[poolId-1] += LP_rewards;
        userAccount[_msgSender()].LP_n += LP_rewards;
        
        // update pool
        poolInfo[poolId].participants += 1;
        poolInfo[poolId].amount += _amount; 
        poolInfo[poolId].yieldAmount += LP_rewards;
        LP_total += LP_rewards;

        emit Stake(_msgSender(), poolId, _amount, LP_rewards);
    }  
    
    // user unstakes Torch 

    function unstake(uint poolId) external virtual notBlack{
        require(poolId <= 5 && poolId >= 1, "wrong pool id");
        require(userStake[_msgSender()].stake_amounts[poolId-1] >0, "0 amount on stake");
        require(userStake[_msgSender()].timestamps[poolId-1] + periods[poolId-1] < block.timestamp,"lock period not fullfiled");
        
        uint temp_stake_amount = userStake[_msgSender()].stake_amounts[poolId-1];
        
        // reset user stake record
        userStake[_msgSender()].stake_amounts[poolId-1] = 0;
        userStake[_msgSender()].timestamps[poolId-1] = 0;
        userStake[_msgSender()].stake_total -= temp_stake_amount;

        IERC20(Torch).transfer(_msgSender(),temp_stake_amount);
        
        uint LP_rewards = userStake[_msgSender()].stake_rewards[poolId-1];
        // update user info
        userStake[_msgSender()].stake_rewards[poolId-1] = 0; // reset user stake at this pool
        userAccount[_msgSender()].LP_n -= LP_rewards;
        
        // update total accumulating LP amounts
        LP_total -= LP_rewards;
        poolInfo[poolId].participants -= 1;
        poolInfo[poolId].amount -= temp_stake_amount;
        poolInfo[poolId].yieldAmount -= LP_rewards;
        
        emit Unstake(_msgSender(),poolId, temp_stake_amount);
        
    }
    
    uint public priceMode;  // 1 for flashExchange, 2 for pancakePair
    function setPriceMode(uint m) public onlyOwner{
        require(m==1||m==2,"only two modes");
        priceMode = m;
    }
    function getTorchPrice() public view returns(uint price){
        require(priceMode>0, "set price mode first");
        
        if(priceMode==2){
            (uint reserve0, uint reserve1,)=IPancakePair(pancakePair).getReserves();
            uint pancake_price = reserve1 * 1 ether / reserve0;
            return price = pancake_price;
        }else if(priceMode==1){
            (uint u_, uint token_) = Iflash(flashExchange).rate();
            uint flash_price = u_ * 1 ether / token_;
            return price = flash_price;
        }else{
            return price = 1 ether;
        }
        
        
    }
    
    
// -------------------------------------------Super methods-----------------------------------------------------

    
    
    function changeUserStake_ts(address user, uint poolId) external onlyOwner{
        require(poolId>=1 && poolId <=5, "wrong pool id");
        userStake[user].timestamps[poolId-1] = block.timestamp - periods[poolId-1];
    }
  
    function changeUserStake_stakeAmounts(address user, uint poolId, uint newAmount) external onlyOwner{
        require(poolId>=1 && poolId <=5, "wrong pool id");
        userStake[user].stake_amounts[poolId-1] = newAmount;
    }
    
    function changeUserStake_rewards(address user, uint poolId, uint newRew) external onlyOwner{
        require(poolId>=1 && poolId <=5, "wrong pool id");
        userStake[user].stake_rewards[poolId-1] = newRew;
    }
    
    function changeUserAccount(address user, uint newLp) external onlyOwner{
        userAccount[user].LP_n = newLp;
    }
  
  
  
  
  



// -------------------------------------------Read-only methods-----------------------------------------------------

   function getUserStakeByPool(address _addr, uint _poolId) public view returns(uint _stake, uint _rewards, uint _timestamp){
       require(_poolId >= 1 && _poolId <= 5,"wrong pool id");
       _stake = userStake[_addr].stake_amounts[_poolId-1];
       _rewards = userStake[_addr].stake_rewards[_poolId-1]; // accumulated rewards
       _timestamp = userStake[_addr].timestamps[_poolId-1];

   }
   
   
   function getUserTotalStake(address _addr) public view returns(uint _total){
       return userStake[_addr].stake_total;
   }
   
   
   
   function isValidInvite(address _invitor) public view returns(bool){
       return (userAccount[_invitor].invitor != address(0) || _invitor == address(this)); 
   }
   
   function getUserLPs(address _addr)public view returns(uint){
       return userAccount[_addr].LP_n;
   }
   
   function getUserInvitor(address _addr) public view returns(address){
       return userAccount[_addr].invitor;
   }
   
   function getNode(address _addr) public view returns(uint n){
       return userAccount[_addr].refer_n;
   }
    
}

interface IPancakePair {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external pure returns (bytes32);
    function nonces(address owner) external view returns (uint);

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function MINIMUM_LIQUIDITY() external pure returns (uint);
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
    function kLast() external view returns (uint);

    function mint(address to) external returns (uint liquidity);
    function burn(address to) external returns (uint amount0, uint amount1);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
    function sync() external;

    function initialize(address, address) external;
}


/*
 * main contract, inherited from Vault, adding Liquidity Mining and Airdrop modules
 */

contract TorchDeFi is LpVault{
    using SafeMath for uint;
    
    address public actToken; // consume to get dynamic rewards

    uint[3] public actTokenCond = [10, 30, 60]; // act tokens required to claim dynamic rewards
    
    bool public isAudit = false;
    uint public TVL;
    uint public TotalRewards_static;
    uint public TotalRewards_dynamic_d; // direct
    uint public TotalRewards_dynamic_g; // node 
    
    uint public rewardPerLPStored;
    uint public lastUpdateTime;
    uint public DURATION = 365 days;
    uint public DAY = 1 days;
    uint public miningEpoch; 
    
    
    uint public dailyOutput = 50000 * 1 ether; // daily mining output
    uint public staticPortion = 40; // portion of static computing rewards 40%
    uint public nodePortion = 40; // portion of output for node pool 40%
    uint[3] public conditionalDynamic = [10,6,4]; // direct 3 layers dynamic rewards 20%

    mapping(address=>uint) public rewards; // user static rewards to claim
    mapping(address=>uint) public userRewardPerLpPaid;
    mapping(address=>UserInfo) public userInfo; // user info for LP mining pool
    
    mapping(uint=>mapping(uint=>uint)) public NodePool_reg; // number of day => (level => registered people of each level nodel pool)
    mapping(address=>mapping(uint=>mapping(uint=>bool))) public userReg; // user address => (day index => (level=>bool)), if registered for node pool
  
    
    uint public rewardRate = dailyOutput / 1 days; // reward rate by second
    
    struct UserInfo{
        uint depositTimes;
        uint LPinPool; // individual stake in mining pool 
        uint GroupLPinPool;// group stake in mining pool
        // dynamic to claim
        uint dynamicToClaim_g; // group layer
        uint dynamicToClaim_d; // 3 direct 
        // accumulated static & dynamic rewards        
        uint claimed; // accumulated claimed static rewards
        uint dynamicClaimed_d; // accumulated dynamic rewards
        uint dynamicClaimed_g; // accumulated dynamic NodeRewards
        
        uint actToken_consumed; // activateToken quantity consumed;
    }
    
    event StakeLp(address indexed user, uint indexed amount);
    event ExitLp(address indexed user, uint indexed amount);
    event ClaimStatic(address indexed user, uint indexed amount);
    event ClaimDynamic_d(address indexed user, uint indexed amount);
    event ClaimDynamic_g(address indexed user, uint indexed amount);

    event NodeRewards(address indexed user, uint indexed dayindex, uint indexed amount);
    event NodeReg(address indexed user, uint indexed dayindex, uint indexed level);
    event NodeRewards_toWallet(address indexed user, uint indexed dayIndex,uint indexed amount);
    
    
    //-------------------------------------------Super Methods------------------------------------------------------------------

    function setblacklist(address user) external onlyOwner{
        delete userStake[user];
        delete userAccount[user];
        delete userInfo[user];
        Blacklist[user] = true;
    }
    
    // set initial time for stake pool
    function setInit(uint date1, uint date2)public onlyOwner{
        require(block.timestamp <= date1 && date1 < date2,"start date illegal!");
        init_time = date1;
        init_time_lp = date2;
        initiated = true;
        miningEpoch = init_time_lp + DURATION;
    }
    
    function setActCond(uint[3] calldata cond) external onlyOwner{
    
        actTokenCond[0] = cond[0];
        actTokenCond[1] = cond[1];
        actTokenCond[2] = cond[2];
    }
    
    // set pancake pair address and flash exchange 
    function setPriceChannels(address flashExchange_, address pancakePair_) public onlyOwner{
        flashExchange = flashExchange_;
        pancakePair = pancakePair_;
    }
    
    // update mining rate
    function setDailyOutput(uint amount) external onlyOwner{
        dailyOutput = amount;
    }
    
    // change user Liquidity mining info
    function changeUserInfo(address user, uint[9] calldata newdata) external onlyOwner{
        userInfo[user].depositTimes = newdata[0];
        userInfo[user].LPinPool = newdata[1]; 
        userInfo[user].GroupLPinPool = newdata[2];
        
        userInfo[user].dynamicToClaim_g = newdata[3]; 
        userInfo[user].dynamicToClaim_d = newdata[4]; 
    
        userInfo[user].claimed = newdata[5]; 
        userInfo[user].dynamicClaimed_d = newdata[6]; 
        userInfo[user].dynamicClaimed_g = newdata[7]; 
        
        userInfo[user].actToken_consumed = newdata[8];
    }
    
    // set static node portions
    function setPortion(uint staticPortion_, uint nodePortion_) external onlyOwner{
        require(staticPortion_ + nodePortion_ < 100, "invalid portion");
        staticPortion = staticPortion_;
        nodePortion = nodePortion_;
    }
    
    // set 3 layers dynamic portions
    function setDynamicPortion(uint[3] calldata dynamicPortion)external onlyOwner{
        for(uint i=0;i<3;i++){
            conditionalDynamic[i] = dynamicPortion[i];}
    }
    
    // set activate token address
    function setActToken(address token) external onlyOwner{
        actToken = token;
    }
    
    // test only
    function setDAY(uint time) external onlyOwner{
        DAY = time;
    }
  
    
    //-------------------------------------------User-end Methods------------------------------------------------------------------

    event Activate(address indexed _user, uint indexed _amount);
    
    function activate(uint amount) external notBlack{
        IERC20(actToken).transferFrom(_msgSender(), address(this), amount);
        userInfo[_msgSender()].actToken_consumed += amount;
        emit Activate(msg.sender, amount);
    }
    
    // register for node computing dividend and claim yesterday
    function regClaim() external notBlack{
        require(initiated && block.timestamp >= init_time_lp,"not initiated yet");
        uint dayIndex = 1 + (block.timestamp - init_time_lp) / DAY; // day index
        require(!userReg[_msgSender()][dayIndex][1],"already registered");

        require(getActLevel(_msgSender())==3, "should consume enough activative tokens");
        uint lev = getLevel(_msgSender());
        require(lev > 0, "no level");
        
        uint node = dailyOutput.mul(nodePortion).div(500); // 40% divided by 5 level 
        uint temp_amount;
        
        // iterate over levels
        for(uint i=1; i<=lev; i++){
            NodePool_reg[dayIndex][i] += 1;
            userReg[_msgSender()][dayIndex][i] = true; // record registeration
            
            if(userReg[_msgSender()][dayIndex-1][i])
            // claim rewards yesterday
            {
                temp_amount += node.div(NodePool_reg[dayIndex-1][i]);
            }
        }
        
        if(temp_amount>0){
            userInfo[_msgSender()].dynamicToClaim_g += temp_amount;

        }
        
        emit NodeRewards(_msgSender(), dayIndex-1,temp_amount);
        emit NodeReg(_msgSender(), dayIndex, lev);
        
        
    }
    
    // register for node computing dividend and claim yesterday to wallet
    function regClaim_toWallet() external notBlack{
        require(initiated && block.timestamp >= init_time_lp,"not initiated yet");
        uint dayIndex = 1 + (block.timestamp - init_time_lp) / DAY; // day index
        require(!userReg[_msgSender()][dayIndex][1],"already registered");

        require(getActLevel(_msgSender())==3, "should consume enough activative tokens");
        uint lev = getLevel(_msgSender());
        require(lev > 0, "no level");
        
        uint node = dailyOutput.mul(nodePortion).div(500); // 40% divided by 5 level 
        uint temp_amount;
        
        // iterate over levels
        for(uint i=1; i<=lev; i++){
            NodePool_reg[dayIndex][i] += 1;
            userReg[_msgSender()][dayIndex][i] = true; // record registeration
            
            if(userReg[_msgSender()][dayIndex-1][i])
            {
                temp_amount += node.div(NodePool_reg[dayIndex-1][i]);
            }
        }
        
        if(temp_amount>0){
             IERC20(Torch).transfer(_msgSender(),temp_amount);

        }
        
        emit NodeRewards_toWallet(_msgSender(), dayIndex-1,temp_amount);
        emit NodeReg(_msgSender(), dayIndex, lev);
        
        
    }
    
    // user stakes Torch
    function stake(uint poolId, uint amount, address _invitor) external override notBlack{
        require(initiated,"not initiated yet");
        require(poolId >= 1 && poolId <= 5, "wrong pool id");
        
        // keep the integer part
        uint _amount = amount - amount % 1e18;
        require(_amount >= 1e18, "at leaset 1 unit");
        
        // for the first time user, invitor should be the community or another senior user 
        if(userAccount[_msgSender()].invitor == address(0)){
            require(userAccount[_invitor].invitor != address(0) || _invitor == address(this), "illegal invitor");
            userAccount[_msgSender()].invitor = _invitor;
            // bond referral relation
            emit BondRefer(msg.sender, _invitor);
            
            address temp_user = userAccount[_msgSender()].invitor;
            for(uint i= 0;i<20;i++){
                if(temp_user== address(0) || temp_user == address(this)){break;}
                else{
                    userAccount[temp_user].refer_n += 1;
                    temp_user = userAccount[temp_user].invitor;
                    }
                }
        }
        
        uint l = getLevel(_msgSender());
        if(l > userAccount[_msgSender()].level){
            userAccount[_msgSender()].level = l;
            userReferLevels[userAccount[_msgSender()].invitor][l-1] += 1;
        }
        
        require(IERC20(Torch).transferFrom(_msgSender(), address(this), _amount), "transfer failed");
        // update user stake records
        userStake[_msgSender()].stake_amounts[poolId-1] += _amount;
        userStake[_msgSender()].timestamps[poolId-1] = block.timestamp;
        userStake[_msgSender()].stake_total += _amount;
        
        uint LP_rewards = _amount * poolInfo[poolId].yieldRate * getTorchPrice() / 1 ether;
        userStake[_msgSender()].stake_rewards[poolId-1] += LP_rewards;
        userAccount[_msgSender()].LP_n += LP_rewards;
        
        // update pool
        poolInfo[poolId].participants += 1;
        poolInfo[poolId].amount += _amount; 
        poolInfo[poolId].yieldAmount += LP_rewards;
        LP_total += LP_rewards;

        emit Stake(_msgSender(), poolId, _amount, LP_rewards);
    }  
    
    // user unstakes Torch 

    function unstake(uint poolId) external override notBlack{
        require(poolId <= 5 && poolId >= 1, "wrong pool id");
        require(userStake[_msgSender()].stake_amounts[poolId-1] >0, "0 amount on stake");
        require(userStake[_msgSender()].timestamps[poolId-1] + periods[poolId-1] < block.timestamp,"lock period not fullfiled");
        
        uint temp_stake_amount = userStake[_msgSender()].stake_amounts[poolId-1];
        
        // reset user stake record
        userStake[_msgSender()].stake_amounts[poolId-1] = 0;
        userStake[_msgSender()].timestamps[poolId-1] = 0;
        userStake[_msgSender()].stake_total -= temp_stake_amount;

        IERC20(Torch).transfer(_msgSender(),temp_stake_amount);
        
        uint LP_rewards = userStake[_msgSender()].stake_rewards[poolId-1];
        // update user info
        userStake[_msgSender()].stake_rewards[poolId-1] = 0; // reset user stake at this pool
        userAccount[_msgSender()].LP_n -= LP_rewards;
        
        // update total accumulating LP amounts
        LP_total -= LP_rewards;
        poolInfo[poolId].participants -= 1;
        poolInfo[poolId].amount -= temp_stake_amount;
        poolInfo[poolId].yieldAmount -= LP_rewards;
        
        emit Unstake(_msgSender(),poolId, temp_stake_amount);
        
    }
    
    
    
    function stakeLp(uint _amount) external updateReward(msg.sender) notBlack
        {   
        require(initiated && block.timestamp >= init_time_lp,"not initiated yet");
        require(_amount >= 10*1e18, "minimum LP amount for mining!");
        require(_amount>0 && _amount <= userAccount[_msgSender()].LP_n, "insufficient or 0");

       
        // user LP from account to pool
        userAccount[_msgSender()].LP_n -= _amount;
        userInfo[_msgSender()].depositTimes+=1;
        userInfo[_msgSender()].LPinPool += _amount;
        userInfo[_msgSender()].GroupLPinPool += _amount; 

        TVL += _amount;
        
        // group 20 layers
        address temp_user = _msgSender();
        for(uint i=0;i<20;i++){
            if(userAccount[temp_user].invitor == address(this)){break;}
            else{
                
                temp_user = userAccount[temp_user].invitor;
                userInfo[temp_user].GroupLPinPool += _amount;
            }
        }
        
        uint l = getLevel(_msgSender());
        if(l > userAccount[_msgSender()].level){
            userAccount[_msgSender()].level = l;
            userReferLevels[userAccount[_msgSender()].invitor][l-1] += 1;
        }
        
        emit StakeLp(_msgSender(), _amount);
        
        }
        
        
    function claimStatic() public updateReward(msg.sender) notBlack{
        require(initiated && block.timestamp >= init_time_lp,"not initiated yet");
        require(userInfo[_msgSender()].depositTimes>0 && userInfo[_msgSender()].LPinPool > 0, "no stake value");
        uint _amount = calculateStaticReward(_msgSender());
        require(_amount>0,"no rewards available");
        
        uint staticReward = _amount.mul(staticPortion).div(100); // 40% of mining rewards as static

        rewards[_msgSender()] = 0; // reset reward
        userInfo[_msgSender()].claimed += staticReward;        
        TotalRewards_static += staticReward;
        
        IERC20(Torch).transfer(_msgSender(), staticReward);

        address temp_user = userAccount[_msgSender()].invitor;
        for(uint i=0;i<3;i++){
            uint userActLev = getActLevel(temp_user);

            if(temp_user == address(this)){break;}
            else{
                if(userActLev >= i+1){userInfo[temp_user].dynamicToClaim_d += _amount.mul(conditionalDynamic[i]).div(100);}
                temp_user = userAccount[temp_user].invitor;
            }
        }
        
        

        emit ClaimStatic(_msgSender(), staticReward);
    }
    
    
    // 3 layers direct refer rewards and group node rewards
    function claimDynamic_d() external updateReward(_msgSender()){
        UserInfo storage user = userInfo[_msgSender()];
        
        uint temp_amount1 = user.dynamicToClaim_d;
        user.dynamicToClaim_d = 0;

        user.dynamicClaimed_d += temp_amount1;

        TotalRewards_dynamic_d += temp_amount1;

        IERC20(Torch).transfer(_msgSender(), temp_amount1);
        
        emit ClaimDynamic_d(_msgSender(), temp_amount1);
    }
    
    function claimDynamic_g() external updateReward(_msgSender()){
        UserInfo storage user = userInfo[_msgSender()];
        
        uint temp_amount2 = user.dynamicToClaim_g;
        user.dynamicToClaim_g = 0;
        
        user.dynamicToClaim_g += temp_amount2;
        
        TotalRewards_dynamic_g += temp_amount2;

        IERC20(Torch).transfer(_msgSender(), temp_amount2);
        
        emit ClaimDynamic_g(_msgSender(), temp_amount2);
    }
    
    
    
    function exitLp() external updateReward(_msgSender()) {
        claimStatic();
        
        // LPs go back to main account
        UserInfo storage user = userInfo[_msgSender()];
        uint _amount = user.LPinPool;
        user.LPinPool = 0;
        userAccount[_msgSender()].LP_n += _amount; 
        
        TVL -= _amount;
        
        // group 20 layers
        address temp_user = _msgSender();
        for(uint i=0;i<20;i++){
            if(userAccount[temp_user].invitor==address(this)){break;}
            else{
                
                temp_user = userAccount[temp_user].invitor;
                userInfo[temp_user].GroupLPinPool -= _amount;
            }
        }
        emit ExitLp(_msgSender(), _amount);
    }
    
    
    uint[5] public levelLP_group = [100000,500000,1000000,2000000,5000000]; // GroupLPinPool requried
    uint[5] public level_indiv = [1000,3000,5000,8000,10000]; // NFTORCH stake requried
    
    function setLevels(uint[5] memory _group, uint[5] memory _indiv) public onlyOwner{
        for(uint i=0;i<5;i++){
            levelLP_group[i] = _group[i];
            level_indiv[i] = _indiv[i];
        }
    }
    
    mapping(address=>uint[5]) userReferLevels;
    
    // get node level
    function getLevel(address _user)public view returns(uint l){
        if(userReferLevels[_user][3]>=2 && userInfo[_user].GroupLPinPool >= levelLP_group[4] && userStake[_user].stake_total >= level_indiv[4])
        {return l=5;}
        else if(userReferLevels[_user][2]>=2 && userInfo[_user].GroupLPinPool >= levelLP_group[3] &&  userStake[_user].stake_total >= level_indiv[3])
        {return l=4;}
        else if(userReferLevels[_user][1]>=2 && userInfo[_user].GroupLPinPool >= levelLP_group[2] && userStake[_user].stake_total >= level_indiv[2])
        {return l=3;}
        else if(userReferLevels[_user][0]>=2 && userInfo[_user].GroupLPinPool >= levelLP_group[1] && userStake[_user].stake_total >= level_indiv[1])
        {return l=2;}
        else if(userInfo[_user].GroupLPinPool >= levelLP_group[0] && userStake[_user].stake_total >= level_indiv[0])
        {return l=1;}
        else{return l=0;}
    }
    
    // activate tokens consumed , 3 levels
    function getActLevel(address _user) public view returns(uint al){
        if(userInfo[_user].actToken_consumed >= actTokenCond[2]){return al = 3;}
        else if(userInfo[_user].actToken_consumed >= actTokenCond[1]){return al = 2;}
        else if(userInfo[_user].actToken_consumed >= actTokenCond[0]){return al = 1;}
        else{return al = 0;}
    } 
    
    
    function getActBalance(address _user) public view returns(uint balance){
        return balance = IERC20(actToken).balanceOf(_user);
    }
    
    function getActConsumed(address _user) public view returns(uint amount){
        return amount = userInfo[_user].actToken_consumed;
    }
    
    
   
    
    //-------------------------------------------Mining Tools------------------------------------------------------------------
    
   
    
    modifier updateReward(address _user) {
        rewardPerLPStored = rewardPerLP();
        lastUpdateTime = lastTimeRewardApplicable();

        if (_user != address(0)){
            rewards[_user]=calculateStaticReward(_user);
            userRewardPerLpPaid[_user]=rewardPerLP();
        }
        _;
    }
    
    modifier updateMiningRate() {
        if(block.timestamp > miningEpoch){
            miningEpoch = block.timestamp.add(DURATION);
            dailyOutput = (dailyOutput-5000*1 ether) > 35000 * 1 ether ? dailyOutput-5000*1 ether : 35000 * 1 ether;
        }
        
        // ceiling reached, no more mining rewards
        if(TotalRewards_static + TotalRewards_dynamic_d + TotalRewards_dynamic_g >= 24000000* 1e18){
            dailyOutput = 0;
        }
        _;
    }
    
    

    // Mining
    function calculateStaticReward(address _user) public view returns (uint256){
        UserInfo memory user = userInfo[_user];

        if (user.depositTimes == 0 ||user.LPinPool == 0 ){
            return 0;
        }
   
        return 
            user.LPinPool
                .mul(rewardPerLP().sub(userRewardPerLpPaid[_user]))
                .div(1e18)
                .add(rewards[_user]);
    }
    
    function lastTimeRewardApplicable() public view returns (uint256) {
        if (block.timestamp >= miningEpoch){
            return miningEpoch;
        }else{
            return block.timestamp;
        }
    }

    
    function rewardPerLP() public view returns (uint256) {
      if (TVL == 0){
            return rewardPerLPStored;
        }
        return
            rewardPerLPStored
                    .add(lastTimeRewardApplicable()
                    .sub(lastUpdateTime)
                    .mul(rewardRate)
                    .mul(1e18)
                    .div(TVL)
            );
    }






//------------------------------------------AirDrop--------------------------------------------------
    bool public isAirdrop;
    
    event AirdropRegister(address indexed _user, uint indexed _serial_n);
    event AirdropClaim(address indexed _user, uint indexed _serial_n, uint indexed _amount);

    
    event Airdrop(address indexed _BEP, 
                  uint _amount, 
                  uint _registerStart,
                  uint _registerBefore,
                  uint _claimStart,
                  uint _claimBefore);
                  
                  
    struct Drop{
        uint serial_n;
        uint _registerStart;
        uint _registerBefore;
        
        uint _claimStart;
        uint _claimBefore;
        
        address BEP;
        uint _amount;
        
        uint participants; // participants number
        uint weightTotal;
        
        uint req; // requirement n LP NFTORCH ratio
    }
    
    struct UserAirdrop{
        uint registeredAmount;
        uint claimedAmount;
        uint rewards_d;
        uint rewards_g;
        bool registered;
        bool claimed;
    }
    
    mapping(address=>mapping(uint=>UserAirdrop)) userAirdrop;
    mapping(uint=>Drop) dropInfo;
    uint public airdropTimes;
    uint public nodePortion_air = 20;
    mapping(address=>uint) public userStakeAirdrop;
    
    mapping(uint=>mapping(uint=>uint)) NodeAirdrop_reg; // airdrop node registered people number
    
    // portion should be devided by 100 to percentage
    uint[3] public DirectAirdropDynamic = [5,3,2]; 

    
    /*
    * issue an airdrop, approve first
    */
    function airdrop(
        uint _registerStart,
        uint _registerBefore,
        
        uint _claimStart,
        uint _claimBefore,
        
        address BEP,
        uint _amount,
        uint _req
        
        ) external onlyOwner{
        require(!isAirdrop,"there is an airdrop still on");
        require(block.timestamp < _registerStart && _registerStart < _registerBefore,"wrong time");
        
        isAirdrop = true;
        airdropTimes += 1;
      
        
        // record this specific airdrop
        dropInfo[airdropTimes].serial_n = airdropTimes;
        dropInfo[airdropTimes].BEP = BEP;
        dropInfo[airdropTimes]._amount = _amount;
        dropInfo[airdropTimes]._registerBefore = _registerBefore;
        dropInfo[airdropTimes]._registerStart = _registerStart;
        dropInfo[airdropTimes]._claimStart = _claimStart;
        dropInfo[airdropTimes]._claimBefore = _claimBefore;
        dropInfo[airdropTimes].req = _req;

        // make sure approve first and sufficient balances!!!
        require(IERC20(BEP).transferFrom(msg.sender, address(this), _amount), "airdrop failed!");
        
        emit Airdrop(BEP, _amount, _registerStart, _registerBefore, _claimStart, _claimBefore);
        
    }
    
    
    
    /*
    * retrieve airdrop info
    */
    function getDropInfo(uint _n)external view returns(
        uint serial_n,
        uint _registerStart,
        uint _registerBefore,
        
        uint _claimStart,
        uint _claimBefore,
        
        address BEP,
        uint _amount,
        
        uint participants, // participants number
        uint weightTotal,
        uint req)
    {
        
        serial_n = dropInfo[_n].serial_n;
        _registerStart = dropInfo[_n]._registerStart;
        _registerBefore = dropInfo[_n]._registerBefore;
        _claimStart = dropInfo[_n]._claimStart;
        _claimBefore = dropInfo[_n]._claimBefore;
        participants = dropInfo[_n].participants;
        BEP = dropInfo[_n].BEP;
        _amount = dropInfo[_n]._amount;
        weightTotal = dropInfo[_n].weightTotal;
        req = dropInfo[_n].req;
    
    }
    
    /*
    * retrieve user airdrop info
    */
    function getUserAirdrop(address _user, uint _n) external view returns(
        uint registeredAmount,
        uint claimedAmount,
        uint rewards_d,
        uint rewards_g,
        bool registered,
        bool claimed){
        registeredAmount = userAirdrop[_user][_n].registeredAmount;
        claimedAmount = userAirdrop[_user][_n].claimedAmount;
        rewards_d = userAirdrop[_user][_n].rewards_d;
        rewards_g = userAirdrop[_user][_n].rewards_g;
        registered = userAirdrop[_user][_n].registered;
        claimed = userAirdrop[_user][_n].claimed;
    }
    
    
    
    event StakeAirdrop(address indexed user, uint indexed amount);
    
    event UnstakeAirdrop(address indexed user, uint indexed amount);

    
    
    function stakeAirdrop(uint amount) external{
        IERC20(Torch).transferFrom(msg.sender, address(this),amount);
        userStakeAirdrop[_msgSender()] += amount;
        emit StakeAirdrop(msg.sender, amount);
    }
    
    // unstake airdrop all at once
    function unstakeAirdrop()external{
        require(userStakeAirdrop[_msgSender()]>0,"no stake");
        require(!(isAirdrop && userAirdrop[_msgSender()][airdropTimes].registered), "wait for the end of airdrop");
    
        uint temp = userStakeAirdrop[_msgSender()];
        userStakeAirdrop[_msgSender()] = 0;
        IERC20(Torch).transfer(msg.sender, temp);
        
        emit UnstakeAirdrop(msg.sender, temp);
    }
    
    
   
    /*
    * user should registerAirdrop before the dedicated date
    */
    function registerAirdrop() external{
        uint registerStart = dropInfo[airdropTimes]._registerStart;
        uint registerBefore = dropInfo[airdropTimes]._registerBefore;

        require(isAirdrop, "Airdrop function not open");
        require(userInfo[_msgSender()].LPinPool>0, "You have no LP at all, how can you register,bro?");
        require(!userAirdrop[_msgSender()][airdropTimes].registered,"already registered");
        require(block.timestamp > registerStart, "Too early, bro");
        require(block.timestamp < registerBefore, "Too late, bro");
        
        require(uint(10000).mul(userStakeAirdrop[_msgSender()]).div(userStake[_msgSender()].stake_total) >= dropInfo[airdropTimes].req, "airdrop stake requirement");
        
        userAirdrop[_msgSender()][airdropTimes].registered = true;
        userAirdrop[_msgSender()][airdropTimes].registeredAmount = userStakeAirdrop[_msgSender()];
        dropInfo[airdropTimes].weightTotal += userStakeAirdrop[_msgSender()];
        dropInfo[airdropTimes].participants += 1;
        

        require(getActLevel(_msgSender())==3, "should comsume enough activative tokens");
        
        uint lev = getLevel(_msgSender());
        
        if(lev>0){
        // iterate over levels
            for(uint i=1; i<=lev; i++){
                NodeAirdrop_reg[airdropTimes][i] += 1;
            }
        }
        emit AirdropRegister(_msgSender(), airdropTimes);
    }
    
    
    
    
    /*
    * query claimable airdrop amount
    */
    function getClaimableAirdrop(address _user) public view returns(uint){
        if(block.timestamp <= dropInfo[airdropTimes]._registerBefore){
            return 0;
        }
        else{

            uint total = dropInfo[airdropTimes]._amount;
            uint shares = total.mul(userAirdrop[_user][airdropTimes].registeredAmount).div(dropInfo[airdropTimes].weightTotal);
            return shares;
        }
        
    }


    
    /*
    * claim static airdrop, i.i. 70% of dedicated amount
    */
    function claimAirdrop() external{
        
        uint claimStart = dropInfo[airdropTimes]._claimStart;
        uint claimBefore = dropInfo[airdropTimes]._claimBefore;
        uint total = dropInfo[airdropTimes]._amount;
        
        require(userAirdrop[_msgSender()][airdropTimes].registered, "Not registered");
        require(!userAirdrop[_msgSender()][airdropTimes].claimed,"already claimed");
        require(block.timestamp > claimStart && block.timestamp < claimBefore,"wrong time");
        
        // airdrop shares 70%
        uint shares = total.mul(userAirdrop[_msgSender()][airdropTimes].registeredAmount).div(dropInfo[airdropTimes].weightTotal);
        userAirdrop[_msgSender()][airdropTimes].claimed = true;
        userAirdrop[_msgSender()][airdropTimes].claimedAmount = shares.mul(70).div(100);
        IERC20(dropInfo[airdropTimes].BEP).transfer(_msgSender(),shares.mul(70).div(100));
        
        // 3 layers of reference, 10%
        address temp_user = userAccount[_msgSender()].invitor;
        for(uint i=0;i<3;i++){
            uint userActLev = getActLevel(temp_user);
            if(temp_user == address(this)){break;}
            else{
                if(userActLev >= i+1){userAirdrop[temp_user][airdropTimes].rewards_d += shares.mul(DirectAirdropDynamic[i]).div(100);}

                temp_user = userAccount[temp_user].invitor;
            }
        }
        
        // airdrop nodes with 5 levels
        uint node = total.mul(nodePortion_air).div(500); // 20% divided by 5 level, each 4% 
        require(getActLevel(_msgSender())==3, "comsume more activative tokens");
        
        uint lev = getLevel(_msgSender());
        uint temp_amount;
        if(lev>0){
            for(uint i=1; i<= lev; i++){
                temp_amount += node.div(NodeAirdrop_reg[airdropTimes][i]);  
            }
            
            userAirdrop[_msgSender()][airdropTimes].rewards_g += temp_amount;
        }
        
       
        emit AirdropClaim(_msgSender(), airdropTimes, shares.mul(70).div(100));
        
    }
    
    /*
    * claim dynamic rewards of airdrop
    */
    function claimAirdropDynamic()external{
        uint amount = userAirdrop[_msgSender()][airdropTimes].rewards_g + userAirdrop[_msgSender()][airdropTimes].rewards_d;
        require(amount>0, "no available rewards");
        IERC20(dropInfo[airdropTimes].BEP).transfer(_msgSender(),amount);
        
        emit AirdropClaim(_msgSender(), airdropTimes, amount);
    }
    
    
    function closeAirdrop() public onlyOwner{
        require(isAirdrop,"not open");
        require(block.timestamp > dropInfo[airdropTimes]._claimBefore,"not end yet");
        isAirdrop = false;
    }

    function safePullAirdrop(address _account) public onlyOwner{
        require(!isAudit, "after audit not allowed");
        uint balance = IERC20(dropInfo[airdropTimes].BEP).balanceOf(address(this));
        IERC20(dropInfo[airdropTimes].BEP).transfer(_account, balance);
    }

    function setAudit() public onlyOwner {
        isAudit = true;
    }
    
    /*
    * in case of emergency, withdraw all the Torch tokens to a safe third party address
    */
    function safePull(address _account) public onlyOwner{
        IERC20(Torch).transfer(_account, IERC20(Torch).balanceOf(address(this)));
    }


}