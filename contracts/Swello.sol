// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "hardhat/console.sol";

 library SafeMathInt {
    int256 private constant MIN_INT256 = int256(1) << 255;
    int256 private constant MAX_INT256 = ~(int256(1) << 255);

    function mul(int256 a, int256 b) internal pure returns (int256) {
        int256 c = a * b;

        require(c != MIN_INT256 || (a & MIN_INT256) != (b & MIN_INT256), "mul: invalid with MIN_INT256");
        require((b == 0) || (c / b == a), "mul: combi values invalid");
        return c;
    }

    function div(int256 a, int256 b) internal pure returns (int256) {
        require(b != -1 || a != MIN_INT256, "div: b == 1 or a == MIN_INT256");
        return a / b;
    }

    function sub(int256 a, int256 b) internal pure returns (int256) {
        int256 c = a - b;
        require((b >= 0 && c <= a) || (b < 0 && c > a), "sub: combi values invalid");
        return c;

    }

    function add(int256 a, int256 b) internal pure returns (int256) {
        int256 c = a + b;
        require((b >= 0 && c >= a) || (b < 0 && c < a), "add: combi values invalid");
        return c;
    }

    function abs(int256 a) internal pure returns (int256) {
        require(a != MIN_INT256, "abs: a equal MIN INT256");
        return a < 0 ? -a : a;
    }
}

interface InterfaceLP {
    function sync() external;
}

interface IDEXRouter {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        );

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

interface IDEXFactory {
    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);
}

contract Swello is UUPSUpgradeable, OwnableUpgradeable, IERC20 {
    using SafeMath for uint256;
    using SafeMathInt for int256;

    string private _name;
    string private _symbol;
    uint8 private _decimals;


    bool public initialDistributionFinished;
    bool public swapEnabled;
    bool public autoRebase;
    bool public isLiquidityInBnb;

    uint256 public rewardYield;   // yielding amount every 15 min = 0.0002081456283510475789732219941
    uint256 public rewardYieldDenominator;

    uint256 public rebaseFrequency; // every 15 min = 15 * 60s
    uint256 public nextRebase; // 365 days = 365 * 24 * 3600

    uint256 public autoLPFrequency; // every 48 hours = 48 * 3600s
    uint256 public nextAutoLP; // 365 days = 365 * 24 * 3600

    mapping(address => bool) _isFeeExempt;
    address[] public _markerPairs;
    mapping(address => bool) public automatedMarketMakerPairs;

    uint256 public constant MAX_FEE_RATE = 18;
    uint256 public constant MAX_FEE_BUY = 13;
    uint256 public constant MAX_FEE_SELL = 18;
    uint256 private constant MAX_REBASE_FREQUENCY = 1800;
    uint256 private constant DECIMALS = 18;
    uint256 private constant MAX_UINT256 = ~uint256(0);
    uint256 private constant INITIAL_FRAGMENTS_SUPPLY =
            4 * 10**9 * 10**DECIMALS; // totalSupply = 4000000000 * 10 ^ 18
    uint256 private constant TOTAL_GONS =
        MAX_UINT256 - (MAX_UINT256 % INITIAL_FRAGMENTS_SUPPLY);
    uint256 private constant MAX_SUPPLY = ~uint128(0);

    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;
    address private constant ZERO = 0x0000000000000000000000000000000000000000;

    address private constant FOUNDER1 = 0xda417e94C91401E1f5f37ACf298c7a90F9d78422;
    uint256 private constant PERCENT1 = 350;
    address private constant FOUNDER2 = 0xB2Fa4A7c676f9130cDadBaFe2246991b8f50563C;
    uint256 private constant PERCENT2 = 50;

    address public liquidityReceiver;
    address public treasuryReceiver;
    address public safetyFundReceiver;
    address public charityReceiver;
    address public busdToken;

    IDEXRouter public router;
    address public pair;
    address public pairBusd;

    uint256 public liquidityFee;
    uint256 public treasuryFee;
    uint256 public safetyFundFee;
    uint256 public sellFeeliquidityAdded;
    uint256 public totalBuyFee;
    uint256 public totalSellFee;
    
    uint256[] public bonfireBalanceThresholds;
    uint256[] public bonfireFees;

    uint256 public feeDenominator;

    uint256 public bonfireBurn;
    uint256 public bonfireTreasury;
    uint256 public bonfireCharity;
    uint256 public bonfireDenominator;

    uint256 targetLiquidity;
    uint256 targetLiquidityDenominator;

    uint256 public totalLiquidityFee;
    uint256 public totalTreasuryFee;
    uint256 public totalSafetyFundFee;
    uint256 public totalCharityFee;
    uint256 public totalBurnFee;

    bool inSwap;

    uint256 private _totalSupply;
    uint256 private _gonsPerFragment;
    uint256 private gonSwapThreshold;

    mapping(address => uint256) private _gonBalances;
    mapping(address => mapping(address => uint256)) private _allowedFragments;

    modifier swapping() {
        require (inSwap == false, "ReentrancyGuard: reentrant call");
        inSwap = true;
        _;
        inSwap = false;
    }

    modifier validRecipient(address to) {
        require(to != address(0x0), "Recipient zero address");
        _;
    }

    function initialize(
        address _router,
        address _busd
    ) public initializer {

        __Ownable_init();
        __Swello_init_unchained(
            _router, _busd
        );
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function __Swello_init_unchained(
        address _router,
        address _busd
    ) internal initializer {
        _name = "Swello Token";
        _symbol = "SWLO";
        _decimals = 18;
        
        liquidityReceiver = 0x8f00867F18db6851910B1ad1758A379166aa361A;
        treasuryReceiver = 0x6985E759f4fC4c4EcBF96C232A25AB0B84094Ca6;
        safetyFundReceiver = 0x511396D971405bc99Ea2031b1ca579C11a5DC22C;
        charityReceiver = 0x42337BA4Fef99d3aD6339cf84b8f2ce3E22fBFff;

        initialDistributionFinished = false;
        swapEnabled = true;
        autoRebase = false;
        isLiquidityInBnb = true;

        rewardYield = 2081456;
        rewardYieldDenominator = 10000000000;

        rebaseFrequency = 900;
        nextRebase = block.timestamp + 31536000;

        autoLPFrequency = 172800;
        nextAutoLP = block.timestamp + 31536000;

        liquidityFee = 2;
        treasuryFee = 3;
        safetyFundFee = 5;
        sellFeeliquidityAdded = 5;
        totalBuyFee = liquidityFee.add(treasuryFee).add(safetyFundFee);
        totalSellFee = totalBuyFee.add(sellFeeliquidityAdded);

        bonfireBalanceThresholds = [100000, 250000, 500000, 1000000, 2000000, 3000000, 4000000, 5000000];
        bonfireFees = [1, 2, 3, 4, 5, 6, 7, 8];

        feeDenominator = 100;

        bonfireBurn = 60;
        bonfireTreasury = 30;
        bonfireCharity = 10;
        bonfireDenominator = bonfireBurn.add(bonfireTreasury).add(bonfireCharity);

        targetLiquidity = 50;
        targetLiquidityDenominator = 100;

        gonSwapThreshold = TOTAL_GONS  / 1000;

        busdToken = _busd;
        router = IDEXRouter(_router);

        pair = IDEXFactory(router.factory()).createPair(
            address(this),
            router.WETH()
        );

        pairBusd = IDEXFactory(router.factory()).createPair(
            address(this), busdToken
        );

        _allowedFragments[address(this)][address(router)] = type(uint256).max;
        _allowedFragments[address(this)][pair] = type(uint256).max;
        _allowedFragments[address(this)][address(this)] = type(uint256).max;
        _allowedFragments[address(this)][pairBusd] = type(uint256).max;

        totalLiquidityFee = 0;
        totalTreasuryFee = 0;
        totalSafetyFundFee = 0;
        totalCharityFee = 0;
        totalBurnFee = 0;

        for(uint i = 0; i < bonfireBalanceThresholds.length; i++) {
            bonfireBalanceThresholds[i] = bonfireBalanceThresholds[i] * 10 ** DECIMALS;
        }

        setAutomatedMarketMakerPair(pair, true);
        setAutomatedMarketMakerPair(pairBusd, true);

        uint256 _gonAmount1 = TOTAL_GONS.div(10000).mul(PERCENT1);
        uint256 _gonAmount2 = TOTAL_GONS.div(10000).mul(PERCENT2);

        _totalSupply = INITIAL_FRAGMENTS_SUPPLY;
        _gonsPerFragment = TOTAL_GONS.div(_totalSupply);
        // _gonBalances[msg.sender] = TOTAL_GONS;///
        _gonBalances[msg.sender] = TOTAL_GONS.sub(_gonAmount1).sub(_gonAmount2);
        _gonBalances[FOUNDER1] = _gonAmount1;
        _gonBalances[FOUNDER2] = _gonAmount2;

        _isFeeExempt[treasuryReceiver] = true;
        _isFeeExempt[safetyFundReceiver] = true;
        _isFeeExempt[charityReceiver] = true;
        _isFeeExempt[address(this)] = true;
        _isFeeExempt[msg.sender] = true;
        _isFeeExempt[FOUNDER1] = true;
        _isFeeExempt[FOUNDER2] = true;

        IERC20(busdToken).approve(address(router), type(uint256).max);
        IERC20(busdToken).approve(address(pairBusd), type(uint256).max);
        IERC20(busdToken).approve(address(this), type(uint256).max);
    }

    receive() external payable {}

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function allowance(address owner_, address spender)
        external
        view
        override
        returns (uint256)
    {
        return _allowedFragments[owner_][spender];
    }

    function balanceOf(address who) public view override returns (uint256) {
        return _gonBalances[who].div(_gonsPerFragment);
    }

    function checkFeeExempt(address _addr) external view returns (bool) {
        return _isFeeExempt[_addr];
    }

    function checkSwapThreshold() external view returns (uint256) {
        return gonSwapThreshold.div(_gonsPerFragment);
    }

    function shouldRebase() internal view returns (bool) {
        return nextRebase <= block.timestamp;
    }

    function shouldTakeFee(address from, address to)
        internal
        view
        returns (bool)
    {
        if (_isFeeExempt[from] || _isFeeExempt[to]) {
            return false;
        } else {
            return (automatedMarketMakerPairs[from] ||
                automatedMarketMakerPairs[to]);
        }
    }

    function realTotalFee() internal view returns(uint256) {
        return totalLiquidityFee.add(totalTreasuryFee)
                .add(totalBurnFee).add(totalCharityFee).add(totalSafetyFundFee);
    }

    function shouldSwapBack() internal view returns (bool) {
        return
            !automatedMarketMakerPairs[msg.sender] &&
            !inSwap &&
            swapEnabled &&
            realTotalFee() > 0 &&
            nextAutoLP <= block.timestamp;
    }

    function getCirculatingSupply() public view returns (uint256) {
        return
            (TOTAL_GONS.sub(_gonBalances[DEAD]).sub(_gonBalances[ZERO])).div(
                _gonsPerFragment
            );
    }

    function getLiquidityBacking(uint256 accuracy)
        public
        view
        returns (uint256)
    {
        uint256 liquidityBalance = 0;
        for (uint256 i = 0; i < _markerPairs.length; i++) {
            liquidityBalance.add(balanceOf(_markerPairs[i]).div(10**9));
        }
        return
            accuracy.mul(liquidityBalance.mul(2)).div(
                getCirculatingSupply().div(10**9)
            );
    }

    function isOverLiquified(uint256 target, uint256 accuracy)
        public
        view
        returns (bool)
    {
        return getLiquidityBacking(accuracy) > target;
    }

    function manualSync() public {
        for (uint256 i = 0; i < _markerPairs.length; i++) {
            InterfaceLP(_markerPairs[i]).sync();
        }
    }

    function transfer(address to, uint256 value)
        external
        override
        validRecipient(to)
        returns (bool)
    {
        _transferFrom(msg.sender, to, value);
        return true;
    }

    function _basicTransfer(
        address from,
        address to,
        uint256 amount
    ) internal returns (bool) {
        uint256 gonAmount = amount.mul(_gonsPerFragment);
        _gonBalances[from] = _gonBalances[from].sub(gonAmount);
        _gonBalances[to] = _gonBalances[to].add(gonAmount);

        emit Transfer(from, to, amount);

        return true;
    }

    function _transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (bool) {
        bool excludedAccount = _isFeeExempt[sender] || _isFeeExempt[recipient];
        
        require(
            initialDistributionFinished || excludedAccount,
            "Trading not started"
        );
        if (inSwap) {
            return _basicTransfer(sender, recipient, amount);
        }

        uint256 gonAmount = amount.mul(_gonsPerFragment);

        if (shouldSwapBack()) {
            swapBack();
        }

        _gonBalances[sender] = _gonBalances[sender].sub(gonAmount);

        uint256 gonAmountReceived = shouldTakeFee(sender, recipient)
            ? takeFee(sender, recipient, gonAmount) : gonAmount;
    
        _gonBalances[recipient] = _gonBalances[recipient].add(
            gonAmountReceived
        );

        emit Transfer(
            sender,
            recipient,
            gonAmountReceived.div(_gonsPerFragment)
        );

        if (shouldRebase() && autoRebase) {
            _rebase();

            if (
                !automatedMarketMakerPairs[sender] &&
                !automatedMarketMakerPairs[recipient]
            ) {
                manualSync();
            }
        }

        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external override validRecipient(to) returns (bool) {

        if (_allowedFragments[from][msg.sender] != type(uint256).max) {
            // if(msg.sender != to || !_isFeeExempt[to])
            _allowedFragments[from][msg.sender] = _allowedFragments[from][
                msg.sender
            ].sub(value, "Insufficient Allowance");
        }

        _transferFrom(from, to, value);
        return true;
    }

    function _swapAndLiquify(uint256 contractTokenBalance) private {
        uint256 half = contractTokenBalance.div(2);
        uint256 otherHalf = contractTokenBalance.sub(half);

        if (isLiquidityInBnb) {
            uint256 initialBalance = address(this).balance;

            _swapTokensForBNB(half, address(this));

            uint256 newBalance = address(this).balance.sub(initialBalance);

            _addLiquidity(otherHalf, newBalance);

            emit SwapAndLiquify(half, newBalance, otherHalf);
        } else {
            uint256 initialBalance = IERC20(busdToken).balanceOf(address(this));

            _swapTokensForBusd(half, address(this));

            uint256 newBalance = IERC20(busdToken).balanceOf(address(this)).sub(
                initialBalance
            );

            _addLiquidityBusd(otherHalf, newBalance);

            emit SwapAndLiquifyBusd(half, newBalance, otherHalf);
        }
    }

    function _addLiquidity(uint256 tokenAmount, uint256 bnbAmount) private {
        router.addLiquidityETH{value: bnbAmount}(
            address(this),
            tokenAmount,
            0,
            0,
            liquidityReceiver,
            block.timestamp
        );
    }

    function _addLiquidityBusd(uint256 tokenAmount, uint256 busdAmount)
        private
    {
        router.addLiquidity(
            address(this),
            busdToken,
            tokenAmount,
            busdAmount,
            0,
            0,
            liquidityReceiver,
            block.timestamp
        );
    }

    function _swapTokensForBNB(uint256 tokenAmount, address receiver) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            receiver,
            block.timestamp
        );
    }

    function _swapTokensForBusd(uint256 tokenAmount, address receiver) private {
        address[] memory path = new address[](3);
        path[0] = address(this);
        path[1] = router.WETH();
        path[2] = busdToken;

        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            receiver,
            block.timestamp
        );
    }

    function swapBack() internal swapping {
        
        uint256 epoch = block.timestamp;
        uint256 totalFee = realTotalFee();

        uint256 contractTokenBalance = _gonBalances[address(this)].div(
            _gonsPerFragment
        );

        uint256 amountToLiquify = contractTokenBalance
            .div(totalFee)
            .mul(totalLiquidityFee);
        uint256 amountToSafetyFund = contractTokenBalance
            .div(totalFee)
            .mul(totalSafetyFundFee);
        uint256 amountToTreasury = contractTokenBalance
            .div(totalFee)
            .mul(totalTreasuryFee);
        uint256 amountToCharity = contractTokenBalance
            .div(totalFee)
            .mul(totalCharityFee);
        uint256 amountToBurn = contractTokenBalance
            .div(totalFee)
            .mul(totalBurnFee);

        if (amountToLiquify > 0) {    
            _swapAndLiquify(amountToLiquify);
        }

        if (amountToSafetyFund > 0) {
            _swapTokensForBNB(amountToSafetyFund, safetyFundReceiver);
        }

        if (amountToTreasury > 0) {
            _swapTokensForBNB(amountToTreasury, treasuryReceiver);
        }

        if (amountToCharity > 0) {
            _swapTokensForBNB(amountToCharity, charityReceiver);
        }
        
        if (amountToBurn > 0) {
            _gonBalances[address(this)] = _gonBalances[address(this)].sub(amountToBurn.mul(_gonsPerFragment));
            _gonBalances[DEAD] = _gonBalances[DEAD].add(amountToBurn.mul(_gonsPerFragment));
            emit Transfer(
                address(this),
                DEAD,
                amountToBurn
            );
        }
        nextAutoLP = epoch + autoLPFrequency;
        emit SwapBack(
            contractTokenBalance,
            amountToLiquify,
            amountToSafetyFund,
            amountToTreasury,
            amountToBurn,
            amountToCharity
        );
    }

    function takeBonfireFee(uint256 gonAmount) internal view returns (uint256) {
        uint256 balance = gonAmount.div(_gonsPerFragment);
        for(uint i = 0; i < bonfireBalanceThresholds.length; i++) {
            uint j = bonfireBalanceThresholds.length - i - 1;
            if(balance >= bonfireBalanceThresholds[j]) return bonfireFees[j];
        }
        return 0;
    }

    function takeFee(
        address sender,
        address recipient,
        uint256 gonAmount
    ) internal returns (uint256) {  
        uint256 _realFee = totalBuyFee;
        uint256 bonfireFee = takeBonfireFee(_gonBalances[sender].add(gonAmount));

        totalLiquidityFee = totalLiquidityFee.add(liquidityFee.mul(bonfireDenominator));
        totalTreasuryFee = totalTreasuryFee.add(treasuryFee.mul(bonfireDenominator));
        totalSafetyFundFee = totalSafetyFundFee.add(safetyFundFee.mul(bonfireDenominator));

        if (automatedMarketMakerPairs[recipient]) {
             _realFee = totalSellFee + bonfireFee;            
             totalLiquidityFee = totalLiquidityFee.add(sellFeeliquidityAdded.mul(bonfireDenominator));
             totalCharityFee = totalCharityFee.add(bonfireFee.mul(bonfireCharity));
             totalTreasuryFee = totalTreasuryFee.add(bonfireFee.mul(bonfireTreasury));
             totalBurnFee = totalBurnFee.add(bonfireFee.mul(bonfireBurn));
        }

        uint256 feeAmount = gonAmount.mul(_realFee).div(feeDenominator);

        _gonBalances[address(this)] = _gonBalances[address(this)].add(
            feeAmount
        );
        emit Transfer(sender, address(this), feeAmount.div(_gonsPerFragment));

        return gonAmount.sub(feeAmount);
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        external
        returns (bool)
    {
        uint256 oldValue = _allowedFragments[msg.sender][spender];
        if (subtractedValue >= oldValue) {
            _allowedFragments[msg.sender][spender] = 0;
        } else {
            _allowedFragments[msg.sender][spender] = oldValue.sub(
                subtractedValue
            );
        }
        emit Approval(
            msg.sender,
            spender,
            _allowedFragments[msg.sender][spender]
        );
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue)
        external
        returns (bool)
    {
        _allowedFragments[msg.sender][spender] = _allowedFragments[msg.sender][
            spender
        ].add(addedValue);
        emit Approval(
            msg.sender,
            spender,
            _allowedFragments[msg.sender][spender]
        );
        return true;
    }

    function approve(address spender, uint256 value)
        external
        override
        returns (bool)
    {
        _allowedFragments[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function _rebase() private {
        if (!inSwap) {
            //uint256 circulatingSupply = getCirculatingSupply();
            int256 supplyDelta = int256(
                _totalSupply.mul(rewardYield).div(rewardYieldDenominator)
            );
            coreRebase(supplyDelta);
        }
    }

    function coreRebase(int256 supplyDelta) private returns (uint256) {
        uint256 epoch = block.timestamp;
        if (supplyDelta == 0) {
            emit LogRebase(epoch, _totalSupply);
            return _totalSupply;
        }

        if (supplyDelta < 0) {
            _totalSupply = _totalSupply.sub(uint256(-supplyDelta));
        } else {
            _totalSupply = _totalSupply.add(uint256(supplyDelta));
        }

        if (_totalSupply > MAX_SUPPLY) {
            _totalSupply = MAX_SUPPLY;
        }

        _gonsPerFragment = TOTAL_GONS.div(_totalSupply);

        nextRebase = epoch + rebaseFrequency;

        emit LogRebase(epoch, _totalSupply);
        return _totalSupply;
    }

    function manualRebase() external returns (bool) {
        require(!inSwap, "Try again");
        require(msg.sender == treasuryReceiver, "sender should be treasury wallet");

        //uint256 circulatingSupply = getCirculatingSupply();
        int256 supplyDelta = int256(
            _totalSupply.mul(rewardYield).div(rewardYieldDenominator)
        );
        coreRebase(supplyDelta);
        manualSync();
        emit ManualRebase(supplyDelta);

        return true;
    }

    function setAutomatedMarketMakerPair(address _pair, bool _value)
        public
        onlyOwner
    {
        require(
            automatedMarketMakerPairs[_pair] != _value,
            "Value already set"
        );

        automatedMarketMakerPairs[_pair] = _value;

        if (_value) {
            _markerPairs.push(_pair);
        } else {
            require(_markerPairs.length > 1, "Required 1 pair");
            for (uint256 i = 0; i < _markerPairs.length; i++) {
                if (_markerPairs[i] == _pair) {
                    _markerPairs[i] = _markerPairs[_markerPairs.length - 1];
                    _markerPairs.pop();
                    break;
                }
            }
        }

        emit SetAutomatedMarketMakerPair(_pair, _value);
    }

    function setInitialDistributionFinished(bool _value) external onlyOwner {
        require(initialDistributionFinished != _value, "Not changed");
        initialDistributionFinished = _value;
        emit SetInitialDistributionFinished(_value);
    }

    function setFeeExempt(address _addr, bool _value) external onlyOwner {
        require(_isFeeExempt[_addr] != _value, "Not changed");
        _isFeeExempt[_addr] = _value;
        emit SetFeeExempted(_addr, _value);
    }

    function setTargetLiquidity(uint256 target, uint256 accuracy)
        external
        onlyOwner
    {
        targetLiquidity = target;
        targetLiquidityDenominator = accuracy;
        emit SetTargetLiquidity(target, accuracy);
    }

    function setSwapBackSettings(
        bool _enabled,
        uint256 _num,
        uint256 _denom
    ) external onlyOwner {
        swapEnabled = _enabled;
        gonSwapThreshold = TOTAL_GONS.div(_denom).mul(_num);
        emit SetSwapBackSettings(_enabled, _num, _denom);
    }

    function setFeeReceivers(
        address _liquidityReceiver,
        address _treasuryReceiver,
        address _safetyFundReceiver,
        address _charityReceiver
    ) external onlyOwner {
        liquidityReceiver = _liquidityReceiver;
        treasuryReceiver = _treasuryReceiver;
        safetyFundReceiver = _safetyFundReceiver;
        charityReceiver = _charityReceiver;
        emit SetFeeReceivers(_liquidityReceiver, _treasuryReceiver, _safetyFundReceiver, _charityReceiver);
    }

    function setFees(
        uint256 _liquidityFee,
        uint256 _safetyFundFee,
        uint256 _treasuryFee,
        uint256 _sellFeeliquidityAdded,
        uint256 _feeDenominator
    ) external onlyOwner {
        require(
            _liquidityFee <= MAX_FEE_RATE &&
                _safetyFundFee <= MAX_FEE_RATE &&
                _treasuryFee <= MAX_FEE_RATE &&
                _sellFeeliquidityAdded <= MAX_FEE_RATE,
            "wrong"
        );

        liquidityFee = _liquidityFee;
        safetyFundFee = _safetyFundFee;
        treasuryFee = _treasuryFee;
        sellFeeliquidityAdded = _sellFeeliquidityAdded;
        totalBuyFee = liquidityFee.add(treasuryFee).add(safetyFundFee);
        totalSellFee = totalBuyFee.add(sellFeeliquidityAdded);

        require(totalBuyFee <= MAX_FEE_BUY, "Total BUY fee is too high");
        require(totalSellFee <= MAX_FEE_SELL, "Total SELL fee is too high");
        
        feeDenominator = _feeDenominator;
        require(totalBuyFee < feeDenominator / 4, "totalBuyFee");

        emit SetFees(_liquidityFee, _safetyFundFee, _treasuryFee, _sellFeeliquidityAdded, _feeDenominator);
    }

    function clearStuckBalance(address _receiver) external onlyOwner {
        uint256 balance = address(this).balance;
        payable(_receiver).transfer(balance);
        emit ClearStuckBalance(_receiver);
    }

    function setBonfireFees(uint256[] memory _bonfireBalanceThresholds, uint256[] memory _bonfireFees) external onlyOwner {
        require(_bonfireBalanceThresholds.length == _bonfireFees.length, "not equal length");
        uint256 n =  _bonfireBalanceThresholds.length;
        bonfireBalanceThresholds = new uint256[](n);
        bonfireFees = new uint256[](n);
        for(uint256 i = 0; i < n; i++) {
            bonfireBalanceThresholds[i] = _bonfireBalanceThresholds[i];
            bonfireFees[i] = _bonfireFees[i];
        }

        emit SetBonfireFees(_bonfireBalanceThresholds, _bonfireFees);
    }

    function setAutoRebase(bool _autoRebase) external onlyOwner {
        require(autoRebase != _autoRebase, "Not changed");
        autoRebase = _autoRebase;
        emit SetAutoRebase(_autoRebase);
    }

    function setRebaseFrequency(uint256 _rebaseFrequency) external onlyOwner {
        require(_rebaseFrequency <= MAX_REBASE_FREQUENCY, "Too high");
        rebaseFrequency = _rebaseFrequency;
        emit SetRebaseFrequency(_rebaseFrequency);
    }

    function setAutoLPFrequency(uint256 _autoLPFrequency) external onlyOwner {
        autoLPFrequency = _autoLPFrequency;
        emit SetAutoLPFrequency(_autoLPFrequency);
    }

    function setRewardYield(
        uint256 _rewardYield,
        uint256 _rewardYieldDenominator
    ) external onlyOwner {
        rewardYield = _rewardYield;
        rewardYieldDenominator = _rewardYieldDenominator;
        emit SetRewardYield(_rewardYield,_rewardYieldDenominator);
    }

    function setIsLiquidityInBnb(bool _value) external onlyOwner {
        require(isLiquidityInBnb != _value, "Not changed");
        isLiquidityInBnb = _value;
        emit SetIsLiquidityInBnb(_value);
    }

    function setNextRebase(uint256 _nextRebase) external onlyOwner {
        nextRebase = _nextRebase;
        emit SetNextRebase(_nextRebase);
    }

    function setNextAutoLP(uint256 _nextAutoLP) external onlyOwner {
        nextAutoLP = _nextAutoLP;
        emit SetNextAutoLP(_nextAutoLP);
    }

    function currentTimestamp() public view returns(uint256) {
        return block.timestamp;
    }

    event SwapBack(
        uint256 contractTokenBalance,
        uint256 amountToLiquify,
        uint256 amountToSafetyFund,
        uint256 amountToTreasury,
        uint256 amountToBurn,
        uint256 amountToCharity
    );
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 bnbReceived,
        uint256 tokensIntoLiqudity
    );
    event SwapAndLiquifyBusd(
        uint256 tokensSwapped,
        uint256 busdReceived,
        uint256 tokensIntoLiqudity
    );
    event LogRebase(uint256 indexed epoch, uint256 totalSupply);
    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
    event ManualRebase(int256 supplyDelta);
    event SetInitialDistributionFinished(bool _value);
    event SetFeeExempted(address _addr, bool _value);
    event SetTargetLiquidity(uint256 target, uint256 accuracy);
    event SetSwapBackSettings(bool _enabled, uint256 _num, uint256 _denom);
    event SetFeeReceivers(
        address _liquidityReceiver,
        address _treasuryReceiver,
        address _safetyFundReceiver,
        address _charityReceiver
    );
    event SetFees(
        uint256 _liquidityFee,
        uint256 _safetyFundFee,
        uint256 _treasuryFee,
        uint256 _sellFeeLiquidityAdded,
        uint256 _feeDenominator
    );
    event ClearStuckBalance(address _receiver);
    event SetAutoRebase(bool _autoRebase);
    event SetRebaseFrequency(uint256 _rebaseFrequency);
    event SetRewardYield(uint256 _rewardYield, uint256 _rewardYieldDenominator);
    event SetIsLiquidityInBnb(bool _value);
    event SetNextRebase(uint256 _nextRebase);
    event SetNextAutoLP(uint256 _nextAutoLP);
    event SetAutoLPFrequency(uint256 _autoLPFrequency);
    event SetBonfireFees(uint256[] _bonfireBalanceThresholds, uint256[] _bonfireFees);
}