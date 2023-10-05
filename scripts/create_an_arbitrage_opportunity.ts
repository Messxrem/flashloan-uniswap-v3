//npx hardhat run scripts/create_an_arbitrage_opportunity.js --network local
const { ethers } = require("hardhat");
const ERC20ABI = require("../abi/ERC20.json");
const UniswapV3Pool = require("@uniswap/v3-core/artifacts/contracts/UniswapV3Pool.sol/UniswapV3Pool.json");

const provider = ethers.provider;

const WETHAddress = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";

const bn = require('bignumber.js')
bn.config({ EXPONENTIAL_AT: 999999, DECIMAL_PLACES: 40 })

function encodePriceSqrt(reserve1: number, reserve0: number) {
  return ethers.BigNumber.from(
    new bn(reserve1.toString())
      .div(reserve0.toString())
      .sqrt()
      .multipliedBy(new bn(2).pow(96))
      .integerValue(3)
      .toString()
  )
}

async function main() {

  const signer = (await ethers.getSigners())[0];

  console.log("Depolyer's balance: ", await provider.getBalance(signer.address));

  const Factory = await ethers.getContractFactory("BaseTokenWithLiquidity");
  const tokenContract = await Factory.deploy();
  await tokenContract.waitForDeployment();

  const tokenAddress = tokenContract.address;
  console.log('Base token deployed to', tokenAddress);

  if (tokenAddress > WETHAddress) {

    //let contractBalance = await tokenContract.balanceOf(tokenAddress);
    //console.log("Contract balance: ", contractBalance);

    //обернуть немного эфира и отправить WETH на контракт
    let amountIn = ethers.utils.parseEther('10');
    await signer.sendTransaction({ to: WETHAddress, value: amountIn });
    let WETHcontract = new ethers.Contract(WETHAddress, ERC20ABI, provider);
    await WETHcontract.connect(signer).transfer(tokenAddress, amountIn);

    //посмотреть, адрес какого токена меньше
    const token0 = WETHAddress;
    const token1 = tokenAddress;
    let token0price;
    let token1price;
    let token0price2;
    let token1price2;

    if (WETHAddress < tokenAddress) {
      console.log("weth < base");
      token0price = 100;
      token1price = 1;
      token0price2 = 200;
      token1price2 = 1;
    }
    else {
      token0price = 1;
      token1price = 100;
      token0price2 = 1;
      token1price2 = 200;
    }

    //создать 1й пул с ценой 1BASE = 0.001WETH
    let receipt;
    let txPool = await tokenContract.connect(signer).createPool(token0, token1, encodePriceSqrt(token0price, token1price), 500);
    receipt = await txPool.wait();
    let poolAddress = await tokenContract.pool();
    console.log("pool1Address:", poolAddress);
    let poolContract = new ethers.Contract(poolAddress, UniswapV3Pool.abi, provider);
    let txProving = await tokenContract.connect(signer).provideLiq(token0, token1, 500);
    receipt = await txProving.wait();
    console.log("Liquidity after providing: ", await poolContract.liquidity());

    //создать 2й пул с ценой 1BASE = 0.0005WETH

    //обернуть немного эфира и отправить WETH на контракт
    amountIn = ethers.utils.parseEther('10');
    await signer.sendTransaction({ to: WETHAddress, value: amountIn });
    WETHcontract = new ethers.Contract(WETHAddress, ERC20ABI, provider);
    await WETHcontract.connect(signer).transfer(tokenAddress, amountIn);


    console.log(await tokenContract.balanceOf(tokenAddress));
    console.log(await WETHcontract.balanceOf(tokenAddress));

    txPool = await tokenContract.connect(signer).createPool(token0, token1, encodePriceSqrt(token0price2, token1price2), 100);
    receipt = await txPool.wait();
    poolAddress = await tokenContract.pool();
    console.log("pool2Address:", poolAddress);
    poolContract = new ethers.Contract(poolAddress, UniswapV3Pool.abi, provider);
    txProving = await tokenContract.connect(signer).provideLiq(token0, token1, 100);
    receipt = await txProving.wait();
    console.log("Liquidity after providing: ", await poolContract.liquidity());

  }
  else{
    console.log("weth > base, try again!");
  }

}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});