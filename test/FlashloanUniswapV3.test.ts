import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { ethers } from "hardhat";
import { expect } from "chai";
import "@nomicfoundation/hardhat-chai-matchers";
export { loadFixture, ethers, expect };
const ERC20ABI = require('../abi/ERC20.json');

const WETH = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
const PoolAddressesProvider = "0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e";

const BaseTokenAddress = "0xF631eb60D0A403499A8Df8CBd22935e0c0406D72";
const pool1Address = "0x202B3aCf1788cAccf6db649D3A749F30111221e9";
const pool2Address = "0x7fED6ef78cA6f45Ff70dc2Fb8040BAA82F9CFc8c";

describe("FlashloanUniswapV3", () => {

    async function deploy() {
        const signer = (await ethers.getSigners())[0];

        const Factory = await ethers.getContractFactory("FlashloanUniswapV3");
        const flExampleContract = await Factory.deploy(
            PoolAddressesProvider, 
            signer.address,
            WETH,
            BaseTokenAddress,
            pool1Address,
            pool2Address
        );

        await flExampleContract.waitForDeployment();

        return { flExampleContract, signer }
    }

    it("should be deployed", async () => {
        const { flExampleContract } = await loadFixture(deploy);

        expect(flExampleContract.target).to.be.properAddress;
    });

    it("should be executed", async () => {
        const { flExampleContract, signer } = await loadFixture(deploy);

        const WETHcontract = new ethers.Contract(WETH, ERC20ABI, provider);
        const balanceBefore = await WETHcontract.balanceOf(signer.address);

        const amountToBorrow = ethers.parseEther('0.05');
        const txFlashLoan = await flExampleContract.connect(signer).fn_RequestFlashLoan(WETH, amountToBorrow);
        const receipt = await txFlashLoan.wait();
        console.log(receipt);

        const balanceAfter = await WETHcontract.balanceOf(signer.address);

        const profit = balanceAfter - balanceBefore;
        console.log("profit: ",profit);
    });
});