// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./DoctorDogeDividendTracker.sol";
import "./SafeMath.sol";
import "./Ownable.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Router02.sol";

contract DoctorDoge is ERC20, Ownable {
    using SafeMath for uint256;

    IUniswapV2Router02 public uniswapV2Router;
    address public immutable uniswapV2Pair;

    bool private inSwapAndLiquify;

    bool public swapAndLiquifyEnabled = true;

    DoctorDogeDividendTracker public dividendTracker;

    uint256 public maxSellTransactionAmount = 10**6 * (10**18);
    uint256 public swapTokensAtAmount = 2 * 10**5 * (10**18);

    uint256 public immutable BNBRewardsFee;
    uint256 public immutable liquidityFee;
    uint256 public immutable buyFees;
    uint256 public immutable sellFees;

    uint256 public immutable lp_bnbRew_ratio = 6;

    // use by default 300,000 gas to process auto-claiming dividends
    uint256 public gasForProcessing = 300000;

    // exlcude from fees and max transaction amount
    mapping (address => bool) private _isExcludedFromFees;
    
    mapping(address => bool) private _isExcludedFromMaxTx;

    // store addresses that a automatic market maker pairs. Any transfer *to* these addresses
    // could be subject to a maximum transfer amount
    mapping (address => bool) public automatedMarketMakerPairs;

    event UpdateUniswapV2Router(address indexed newAddress, address indexed oldAddress);

    event ExcludeFromFees(address indexed account, bool isExcluded);
    event ExcludeMultipleAccountsFromFees(address[] accounts, bool isExcluded);

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

    event GasForProcessingUpdated(uint256 indexed newValue, uint256 indexed oldValue);

    event SwapAndLiquifyEnabledUpdated(bool enabled);

    event SwapAndLiquify(
        uint256 tokensIntoLiqudity,
        uint256 ethReceived
    );

    event SendDividends(
    	uint256 tokensSwapped,
    	uint256 amount
    );

    event ProcessedDividendTracker(
    	uint256 iterations,
    	uint256 claims,
        uint256 lastProcessedIndex,
    	bool indexed automatic,
    	uint256 gas,
    	address indexed processor
    );

    modifier lockTheSwap {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    constructor() ERC20("Doctor Doge", "DC") {
        uint256 _BNBRewardsFee = 100;
        uint256 _liquidityFee = 20;

        BNBRewardsFee = _BNBRewardsFee;
        liquidityFee = _liquidityFee;
        buyFees = _BNBRewardsFee.add(_liquidityFee);
        sellFees = 175;

    	dividendTracker = new DoctorDogeDividendTracker();
    	
    //	IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3);

    	IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
         // Create a uniswap pair for this new token
        address _uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = _uniswapV2Pair;

        _setAutomatedMarketMakerPair(_uniswapV2Pair, true);

        // exclude from receiving dividends
        dividendTracker.excludeFromDividends(address(dividendTracker));
        dividendTracker.excludeFromDividends(address(this));
        dividendTracker.excludeFromDividends(owner());
        dividendTracker.excludeFromDividends(address(_uniswapV2Router));
        dividendTracker.excludeFromDividends(0x000000000000000000000000000000000000dEaD);

        // exclude from paying fees or having max transaction amount
        excludeFromFees(owner(), true);
        excludeFromFees(address(this), true);
        
        // exclude from max tx
        _isExcludedFromMaxTx[owner()] = true;
        _isExcludedFromMaxTx[address(this)] = true;

        /*
            _mint is an internal function in ERC20.sol that is only called here,
            and CANNOT be called ever again
        */
        _mint(owner(), 10**9 * (10**18));
    }

    receive() external payable {

  	}

    function updateUniswapV2Router(address newAddress) public onlyOwner {
        require(newAddress != address(uniswapV2Router), "DoctorDoge: The router already has that address");
        emit UpdateUniswapV2Router(newAddress, address(uniswapV2Router));
        uniswapV2Router = IUniswapV2Router02(newAddress);
    }

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        require(_isExcludedFromFees[account] != excluded, "DoctorDoge: Account is already the value of 'excluded'");
        _isExcludedFromFees[account] = excluded;
        emit ExcludeFromFees(account, excluded);
    }
    
    function setExcludeFromMaxTx(address _address, bool value) public onlyOwner { 
        _isExcludedFromMaxTx[_address] = value;
    }

    function setExcludeFromAll(address _address) public onlyOwner {
        _isExcludedFromMaxTx[_address] = true;
        _isExcludedFromFees[_address] = true;
        dividendTracker.excludeFromDividends(_address);
    }

    function excludeMultipleAccountsFromFees(address[] calldata accounts, bool excluded) public onlyOwner {
        for(uint256 i = 0; i < accounts.length; i++) {
            _isExcludedFromFees[accounts[i]] = excluded;
        }

        emit ExcludeMultipleAccountsFromFees(accounts, excluded);
    }

    function setAutomatedMarketMakerPair(address pair, bool value) public onlyOwner {
        require(pair != uniswapV2Pair, "DoctorDoge: The PancakeSwap pair cannot be removed from automatedMarketMakerPairs");

        _setAutomatedMarketMakerPair(pair, value);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        require(automatedMarketMakerPairs[pair] != value, "DoctorDoge: Automated market maker pair is already set to that value");
        automatedMarketMakerPairs[pair] = value;

        if(value) {
            dividendTracker.excludeFromDividends(pair);
        }

        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function updateGasForProcessing(uint256 newValue) public onlyOwner {
        require(newValue >= 200000 && newValue <= 500000, "DoctorDoge: gasForProcessing must be between 200,000 and 500,000");
        require(newValue != gasForProcessing, "DoctorDoge: Cannot update gasForProcessing to same value");
        emit GasForProcessingUpdated(newValue, gasForProcessing);
        gasForProcessing = newValue;
    }

    function updateClaimWait(uint256 claimWait) external onlyOwner {
        dividendTracker.updateClaimWait(claimWait);
    }

    function getClaimWait() external view returns(uint256) {
        return dividendTracker.claimWait();
    }

    function getTotalDividendsDistributed() external view returns (uint256) {
        return dividendTracker.totalDividendsDistributed();
    }

    function isExcludedFromFees(address account) public view returns(bool) {
        return _isExcludedFromFees[account];
    }
    
    function isExcludedFromMaxTx(address account) public view returns(bool) {
        return _isExcludedFromMaxTx[account];
    }

    function withdrawableDividendOf(address account) public view returns(uint256) {
    	return dividendTracker.withdrawableDividendOf(account);
  	}

	function dividendTokenBalanceOf(address account) public view returns (uint256) {
		return dividendTracker.balanceOf(account);
	}

    function getAccountDividendsInfo(address account)
        external view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
        return dividendTracker.getAccount(account);
    }

	function getAccountDividendsInfoAtIndex(uint256 index)
        external view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
    	return dividendTracker.getAccountAtIndex(index);
    }

	function processDividendTracker(uint256 gas) external {
		(uint256 iterations, uint256 claims, uint256 lastProcessedIndex) = dividendTracker.process(gas);
		emit ProcessedDividendTracker(iterations, claims, lastProcessedIndex, false, gas, tx.origin);
    }

    function claim() external {
		dividendTracker.processAccount(payable(msg.sender), false);
    }

    function getLastProcessedIndex() external view returns(uint256) {
    	return dividendTracker.getLastProcessedIndex();
    }

    function getNumberOfDividendTokenHolders() external view returns(uint256) {
        return dividendTracker.getNumberOfTokenHolders();
    }

//this will be used to exclude from dividends the presale smart contract address
    function excludeFromDividends(address account) external onlyOwner {
        dividendTracker.excludeFromDividends(account);
    }

    function setSwapAndLiquifyEnabled(bool _enabled) public onlyOwner {
        swapAndLiquifyEnabled = _enabled;
        emit SwapAndLiquifyEnabledUpdated(_enabled);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        if(amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        if(automatedMarketMakerPairs[to] && (!_isExcludedFromMaxTx[from]) && (!_isExcludedFromMaxTx[to])){
            require(amount <= maxSellTransactionAmount, "Sell transfer amount exceeds the maxSellTransactionAmount.");
        }

    	uint256 contractTokenBalance = balanceOf(address(this));
        
        bool overMinTokenBalance = contractTokenBalance >= swapTokensAtAmount;
       
        if(
            overMinTokenBalance &&
            !inSwapAndLiquify &&
            !automatedMarketMakerPairs[from] && 
            swapAndLiquifyEnabled
        ) {
            swapAndLiquify(contractTokenBalance);
        }

        // if any account belongs to _isExcludedFromFee account then remove the fee
        if(!_isExcludedFromFees[from] && !_isExcludedFromFees[to]) {

        	uint256 fees;
            if(automatedMarketMakerPairs[to]) {
            fees = amount.mul(sellFees).div(1000);
            }
            else
            {
            fees = amount.mul(buyFees).div(1000);
            }

        	amount = amount.sub(fees);

            super._transfer(from, address(this), fees);
        }

        super._transfer(from, to, amount);

        try dividendTracker.setBalance(payable(from), balanceOf(from)) {} catch {}
        try dividendTracker.setBalance(payable(to), balanceOf(to)) {} catch {}

        if(!inSwapAndLiquify) {
	    	uint256 gas = gasForProcessing;

	    	try dividendTracker.process(gas) returns (uint256 iterations, uint256 claims, uint256 lastProcessedIndex) {
	    		emit ProcessedDividendTracker(iterations, claims, lastProcessedIndex, true, gas, tx.origin);
	    	} 
	    	catch {

	    	}
        }
    }

    function swapAndLiquify(uint256 contractTokenBalance) private lockTheSwap {
        uint256 denominator = lp_bnbRew_ratio.mul(2);
        uint256 tokensToAddLiquidityWith = contractTokenBalance.div(denominator); //we keep the 1.5% in case of buy, 1.75% in case of sell to add liquidity
        uint256 toSwap = contractTokenBalance.sub(tokensToAddLiquidityWith);//we keep the 13.5% in case of buy, 15.75% in case of sell to swap them to get BNB

        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;

        // swap tokens for ETH
        swapTokensForEth(toSwap); // <- this breaks the ETH -> HATE swap when swap+liquify is triggered

        uint256 deltaBalance = address(this).balance.sub(initialBalance);
        uint256 bnbToAddLiquidityWith = deltaBalance.div(denominator.sub(1)); //we take an amount of bnb worth like tokensToAddLiquidityWith
        
        // add liquidity to uniswap
        addLiquidity(tokensToAddLiquidityWith, bnbToAddLiquidityWith);

        uint256 dividends = address(this).balance;
        (bool success,) = address(dividendTracker).call{value: dividends}("");

        if(success) {
   	 		emit SendDividends(toSwap.sub(tokensToAddLiquidityWith), dividends);
        }
        
        emit SwapAndLiquify(tokensToAddLiquidityWith, deltaBalance);
    }

    function swapTokensForEth(uint256 tokenAmount) private {

        
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        if(allowance(address(this), address(uniswapV2Router)) < tokenAmount) {
          _approve(address(this), address(uniswapV2Router), ~uint256(0));
        }

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
        
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        
        // add the liquidity
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            owner(),
            block.timestamp
        );
        
    }
    
}