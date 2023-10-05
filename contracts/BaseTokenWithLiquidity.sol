// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

interface INonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint amount0Desired;
        uint amount1Desired;
        uint amount0Min;
        uint amount1Min;
        address recipient;
        uint deadline;
    }

    function mint(
        MintParams calldata params
    )
        external
        payable
        returns (uint tokenId, uint128 liquidity, uint amount0, uint amount1);

    struct IncreaseLiquidityParams {
        uint tokenId;
        uint amount0Desired;
        uint amount1Desired;
        uint amount0Min;
        uint amount1Min;
        uint deadline;
    }

    function increaseLiquidity(
        IncreaseLiquidityParams calldata params
    ) external payable returns (uint128 liquidity, uint amount0, uint amount1);

    struct DecreaseLiquidityParams {
        uint tokenId;
        uint128 liquidity;
        uint amount0Min;
        uint amount1Min;
        uint deadline;
    }

    function decreaseLiquidity(
        DecreaseLiquidityParams calldata params
    ) external payable returns (uint amount0, uint amount1);

    struct CollectParams {
        uint tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    function collect(
        CollectParams calldata params
    ) external payable returns (uint amount0, uint amount1);
}

contract BaseTokenWithLiquidity is ERC20, Ownable {
    address public Uniswap_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address public Uniswap_V3_POSMANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    
    address public pool;
    uint256 public LPTokenID;

    int24 private constant MIN_TICK = -887272;
    int24 private constant MAX_TICK = -MIN_TICK;
    int24 private constant TICK_SPACING = 10;

    IUniswapV3Factory public factory = IUniswapV3Factory(Uniswap_V3_FACTORY);
    INonfungiblePositionManager public nonfungiblePositionManager = INonfungiblePositionManager(Uniswap_V3_POSMANAGER);

    constructor() ERC20("MyBaseToken", "BASE") {
        _mint(msg.sender, 7000 * 10 ** decimals());
        _mint(address(this), 3000 * 10 ** decimals());
    }

    //перед вызовом данной функции мы должны передать на контракт нужное количнство WETH
    //токены данного токена у нас тут уже есть после выполнения конструктора
    function provideLiq(address token0, address token1, uint24 fee) external onlyOwner {
        require(token0 == address(this) || token1 == address(this));
        require(token0 < token1);

        //аппрувим наши токены и токены WETH на адрес позишион менеджера
        uint256 amount0ToAdd = ERC20(token0).balanceOf(address(this));
        uint256 amount1ToAdd = ERC20(token1).balanceOf(address(this));

        ERC20(token0).approve(Uniswap_V3_POSMANAGER, amount0ToAdd);
        ERC20(token1).approve(Uniswap_V3_POSMANAGER, amount1ToAdd);

        INonfungiblePositionManager.MintParams
            memory params = INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: fee,
                // нашу начальную ликвидность размажем по бесконечности
                tickLower: (MIN_TICK / TICK_SPACING) * TICK_SPACING,
                tickUpper: (MAX_TICK / TICK_SPACING) * TICK_SPACING,
                amount0Desired: amount0ToAdd,
                amount1Desired: amount1ToAdd,
                //тут можно ставить 0 с условием что функция выполняется когда ни у кого кроме нас
                //еще нет наших токенов
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this), //заберем LP - NFT на адрес этого контракта
                deadline: block.timestamp + 3600
            });

        uint _tokenId;
        uint128 liquidity;
        uint amount0;
        uint amount1;
        (_tokenId, liquidity, amount0, amount1) = nonfungiblePositionManager
            .mint(params);
        LPTokenID = _tokenId;
    }

    //Перед вызовом данной функции на контракт должны быть переданы наш токен и токен WETH
    function increaseLiquidityCurrentRange(address token0, address token1, uint amount0ToAdd, uint amount1ToAdd) external onlyOwner {
        require(token0 == address(this) || token1 == address(this));
        require(token0 < token1);

        ERC20(token0).approve(Uniswap_V3_POSMANAGER, amount0ToAdd);
        ERC20(token1).approve(Uniswap_V3_POSMANAGER, amount1ToAdd);

        INonfungiblePositionManager.IncreaseLiquidityParams
            memory params = INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: LPTokenID,
                amount0Desired: amount0ToAdd,
                amount1Desired: amount1ToAdd,
                //Подвержено фронтраннингу - как защитить - рассмотрим в будущих уроках
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });
        uint128 liquidity;
        uint amount0;
        uint amount1;
        (liquidity, amount0, amount1) = nonfungiblePositionManager.increaseLiquidity(
            params
        );
    }

    function decreaseLiquidityCurrentRange(uint128 liquidity) external onlyOwner {
        INonfungiblePositionManager.DecreaseLiquidityParams
            memory params = INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: LPTokenID,
                liquidity: liquidity,
                //Подвержено фронтраннингу - как защитить - рассмотрим в будущих уроках
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });
        uint amount0;
        uint amount1;

        (amount0, amount1) = nonfungiblePositionManager.decreaseLiquidity(params);
    }
    

    function createPool(address token0, address token1, uint160 sqrtPriceX96, uint24 fee) external onlyOwner {
        require(token0 == address(this) || token1 == address(this));
        require(token0 < token1);
        pool = factory.createPool(token0, token1, fee);

        IUniswapV3Pool(pool).initialize(sqrtPriceX96);
    }

    function withdrowToken(address token) external onlyOwner{
        ERC20(token).transfer(msg.sender, ERC20(token).balanceOf(address(this)));
    }
}
