const { inputToConfig } = require("@ethereum-waffle/compiler");
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber, constants: { MaxUint256, AddressZero } } = require("ethers");
const PancakeswapPairABI = require("../artifacts/contracts/libs/dexfactory.sol/IPancakeSwapPair.json").abi;

const overrides = {
    gasLimit: 9999999
}

const MINIMUM_LIQUIDITY = BigNumber.from(10).pow(3)

describe("Swello Test", function() {
    let owner;
    let wallet0, wallet1, wallet2, wallet3, wallet4, wallet5, wallet6, wallet7, wallet8;
    let wallet;
    let factory, router, WETH, swello;
    let BUSD, WETHPair, fakePair;
    let liquidityReceiver, treasuryReceiver, safetyFundReceiver, charityReceiver;
    const balances = [45682, 104353, 251234, 512354, 1987777, 2345223, 3128737, 4987654, 5123432];
    const bonfireFee = [0, 1, 2, 3, 4, 5, 6, 7, 8];
    const upgrades = hre.upgrades;

    const expandTo18Decimals = (n) => {
        return BigNumber.from(n).mul(BigNumber.from(10).pow(18))
    }
    beforeEach(async() => {
        [
            owner,
            wallet0, wallet1, wallet2, wallet3, wallet4, wallet5, wallet6, wallet7, wallet8,
            liquidityReceiver, treasuryReceiver, safetyFundReceiver, charityReceiver,
            fakePair,
        ] = await ethers.getSigners();

        wallet = [wallet0, wallet1, wallet2, wallet3, wallet4, wallet5, wallet6, wallet7, wallet8];

        const PancakeFactory = await ethers.getContractFactory("PancakeSwapFactory");      
        factory = await PancakeFactory.deploy(owner.address);
        
        const _WETH = await ethers.getContractFactory("WETH");
        WETH = await _WETH.deploy();


        const Router = await ethers.getContractFactory("PancakeSwapRouter");
        router = await Router.deploy(factory.address, WETH.address);

        

        const _BUSD = await ethers.getContractFactory("BEP20Token");
        BUSD = await _BUSD.deploy();

        const Swello = await ethers.getContractFactory("Swello");
        swello = await upgrades.deployProxy(
            Swello,
            [
              router.address,
              BUSD.address,
            ],
            { initializer: 'initialize', kind: 'uups' }
        );
        await swello.deployed();
        
        const WETHPairAddress = await factory.getPair(WETH.address, swello.address)
        WETHPair = await ethers.getContractAt(PancakeswapPairABI, WETHPairAddress);

        for(let i = 0; i < 9; i++) {
            await swello.transfer(wallet[i].address, expandTo18Decimals(balances[i]));
        }

        swello.setInitialDistributionFinished(true);
    })

    it("initial distribution", async() => {
        let totalSupply = await swello.totalSupply();
        let founder1 = "0xda417e94C91401E1f5f37ACf298c7a90F9d78422";
        let founder2 = "0xB2Fa4A7c676f9130cDadBaFe2246991b8f50563C";
        await expect(await swello.balanceOf(founder1)).to.eq(totalSupply.div(10000).mul(350));
        await expect(await swello.balanceOf(founder2)).to.eq(totalSupply.div(10000).mul(50));
    })

    it("set bonfirefees", async() => {
        const _balances = [104353, 251234, 512354, 1987777, 2345223, 3128737, 4987654, 5123432];
        const _bonfireFee = [2, 3, 4, 5, 6, 8, 9, 11];
        await swello.setBonfireFees(_balances, _bonfireFee);
        for(let i = 0; i < _bonfireFee.length; i++) {
            await expect(await swello.bonfireBalanceThresholds(i)).to.eq(_balances[i]);    
            await expect(await swello.bonfireFees(i)).to.eq(_bonfireFee[i]);
        }
    })

    it("addLiquidity", async() => {
        let swelloAmount = expandTo18Decimals(400);
        let ETHAmount = expandTo18Decimals(4);
        const expectedLiquidity = expandTo18Decimals(40);
        const WETHPairToken0 = await WETHPair.token0();

        await swello.approve(router.address, MaxUint256)
        await expect(router.addLiquidityETH(
            swello.address,
            swelloAmount,
            swelloAmount,
            ETHAmount,
            owner.address,
            MaxUint256,
            { ...overrides, value: ETHAmount }
        ))
        .to.emit(WETHPair, 'Transfer')
        .withArgs(AddressZero, AddressZero, MINIMUM_LIQUIDITY)
        .to.emit(WETHPair, 'Transfer')
        .withArgs(AddressZero, owner.address, expectedLiquidity.sub(MINIMUM_LIQUIDITY))
        .to.emit(WETHPair, 'Sync')
        .withArgs(
            WETHPairToken0 === swello.address ? swelloAmount : ETHAmount,
            WETHPairToken0 === swello.address ? ETHAmount : swelloAmount
        )
        .to.emit(WETHPair, 'Mint')
        .withArgs(
            router.address,
            WETHPairToken0 === swello.address ? swelloAmount : ETHAmount,
            WETHPairToken0 === swello.address ? ETHAmount : swelloAmount
        )
    })

    describe("buy & sell", () => {
        let swelloAmount = expandTo18Decimals(400);
        let ETHAmount = expandTo18Decimals(4);
        let transferAmount = BigNumber.from('5438767543354');
        let gonTransferAmount = transferAmount.mul(10000);
        
        it("sell transfer(using whale wallets)", async() => {
            let sellFee = await swello.totalSellFee();
            let feeDenominator = BigNumber.from(100);
            for(let i = 0; i < 9; i++) {
                const totalFee = sellFee.add(bonfireFee[i]);
                let gonFeeAmount = gonTransferAmount.mul(totalFee).div(feeDenominator);
                let expectedFeeAmount = gonFeeAmount.div(10000);
                let expectedTransferAmount = gonTransferAmount.sub(gonFeeAmount).div(10000);

                const prevTotalLiquidityFee = await swello.totalLiquidityFee();
                const prevTotalTreasuryFee = await swello.totalTreasuryFee();
                const prevTotalSafetyFundFee = await swello.totalSafetyFundFee();
                const prevTotalCharityFee = await swello.totalCharityFee();
                const prevTotalBurnFee = await swello.totalBurnFee();

                await expect(swello.connect(wallet[i]).transfer(WETHPair.address, transferAmount, overrides))
                    .to.emit(swello, 'Transfer')
                    .withArgs(wallet[i].address, swello.address, expectedFeeAmount)
                    .to.emit(swello, 'Transfer')
                    .withArgs(wallet[i].address, WETHPair.address, expectedTransferAmount) 
                
                const totalLiquidityFee = await swello.totalLiquidityFee();
                const totalTreasuryFee = await swello.totalTreasuryFee();
                const totalSafetyFundFee = await swello.totalSafetyFundFee();
                const totalCharityFee = await swello.totalCharityFee();
                const totalBurnFee = await swello.totalBurnFee();

                expect(totalLiquidityFee).to.eq(prevTotalLiquidityFee.add(700));
                expect(totalTreasuryFee).to.eq(prevTotalTreasuryFee.add(300 + bonfireFee[i] * 30));
                expect(totalSafetyFundFee).to.eq(prevTotalSafetyFundFee.add(500));
                expect(totalCharityFee).to.eq(prevTotalCharityFee.add(bonfireFee[i] * 10));
                expect(totalBurnFee).to.eq(prevTotalBurnFee.add(bonfireFee[i] * 60));

                console.log("");
                console.log("<<<<<<<        Sell Fee Trace      >>>>>>>>")
                console.log("seller token balance: ",await swello.balanceOf(wallet[i].address));
                console.log("bonfire fee: ", bonfireFee[i] * 100);
                console.log("total liquidity Fee: ", totalLiquidityFee, prevTotalLiquidityFee, 700);
                console.log("total treasury Fee: ", totalTreasuryFee, prevTotalTreasuryFee, 300 + bonfireFee[i] * 30);
                console.log("total safetyfund Fee: ", totalSafetyFundFee, prevTotalSafetyFundFee, 500);
                console.log("total charity Fee: ", totalCharityFee, prevTotalCharityFee, bonfireFee[i] * 10);
                console.log("total burn Fee: ", totalBurnFee, prevTotalBurnFee, bonfireFee[i] * 60);               
            }
        })

        it("buy transfer", async() => {
            swello.transfer(fakePair.address, expandTo18Decimals(1000));
            await swello.setAutomatedMarketMakerPair(fakePair.address, true);
            
            const buyFee = await swello.totalBuyFee();
            const feeDenominator = BigNumber.from(100);
            const totalFee = buyFee;
            let gonFeeAmount = gonTransferAmount.mul(totalFee).div(feeDenominator);
            let expectedFeeAmount = gonFeeAmount.div(10000);
            let expectedTransferAmount = gonTransferAmount.sub(gonFeeAmount).div(10000);

            for(let i = 0; i < 9; i++) {
                const prevTotalLiquidityFee = await swello.totalLiquidityFee();
                const prevTotalTreasuryFee = await swello.totalTreasuryFee();
                const prevTotalSafetyFundFee = await swello.totalSafetyFundFee();
                const prevTotalCharityFee = await swello.totalCharityFee();
                const prevTotalBurnFee = await swello.totalBurnFee();

                const target = wallet[i];
                await expect(swello.connect(fakePair).transfer(target.address, transferAmount, overrides))
                .to.emit(swello, 'Transfer')
                .withArgs(fakePair.address, swello.address, expectedFeeAmount)
                .to.emit(swello, 'Transfer')
                .withArgs(fakePair.address, target.address, expectedTransferAmount)     

                const totalLiquidityFee = await swello.totalLiquidityFee();
                const totalTreasuryFee = await swello.totalTreasuryFee();
                const totalSafetyFundFee = await swello.totalSafetyFundFee();
                const totalCharityFee = await swello.totalCharityFee();
                const totalBurnFee = await swello.totalBurnFee();

                expect(totalLiquidityFee).to.eq(prevTotalLiquidityFee.add(200));
                expect(totalTreasuryFee).to.eq(prevTotalTreasuryFee.add(300));
                expect(totalSafetyFundFee).to.eq(prevTotalSafetyFundFee.add(500));
                expect(totalCharityFee).to.eq(prevTotalCharityFee);
                expect(totalBurnFee).to.eq(prevTotalBurnFee);

                console.log("");
                console.log("<<<<<<<        Buy Fee Trace      >>>>>>>>")
                console.log("buyer token balance: ", await swello.balanceOf(wallet[i].address));
                console.log("total liquidity Fee: ", totalLiquidityFee, prevTotalLiquidityFee, 700);
                console.log("total treasury Fee: ", totalTreasuryFee, prevTotalTreasuryFee, 300);
                console.log("total safetyfund Fee: ", totalSafetyFundFee, prevTotalSafetyFundFee, 500);
                console.log("total charity Fee: ", totalCharityFee, prevTotalCharityFee, 0);
                console.log("total burn Fee: ", totalBurnFee, prevTotalBurnFee, 0);               
            }
        });
    })

    describe("autostake & autoLP", () => {
        let swelloAmount = expandTo18Decimals(50000);
        let ETHAmount = expandTo18Decimals(500);

        beforeEach(async () => {
            // await swello.transfer(WETHPair.address, swelloAmount)
            // await WETH.deposit({ value: ETHAmount })
            // await WETH.transfer(WETHPair.address, ETHAmount)
            // await WETHPair.mint(owner.address, overrides)
        })

        function sleep(ms) {
            return new Promise(resolve => setTimeout(resolve, ms));
        }

        // it("auto stake(every 15 mins)", async() => {
        //     expect(await swello.autoRebase()).to.eq(true);
        //     let curTime = await swello.currentTimestamp();
        //     await swello.setNextRebase(curTime);

        //     /// every 2 sec for testing
        //     await swello.setRebaseFrequency(2);

        //     const target1 = wallet[1];
        //     const target2 = wallet[2];

        //     for(let i = 0; i < 10; i++) {
        //         const prevBalance = await swello.totalSupply();
        //         const prevTarget1Balance = await swello.balanceOf(target1.address);
        //         const prevTarget2Balance = await swello.balanceOf(target2.address);
        //         let tx = await swello.transfer(wallet[0].address, 10000);
        //         let receipt = await tx.wait();
        //         let rebased = false;
        //         receipt.events?.forEach((x) => {
        //              rebased |= (x.event == "LogRebase");
        //         });
        //         if(rebased) {
        //             const rewardYield = await swello.rewardYield();
        //             const rewardYieldDenominator = await swello.rewardYieldDenominator();
        //             const currentBalance = await swello.totalSupply();
        //             const curTarget1Balance = await swello.balanceOf(target1.address);
        //             const curTarget2Balance = await swello.balanceOf(target2.address);

        //             let reward = prevBalance.mul(rewardYield).div(rewardYieldDenominator);
        //             expect(currentBalance).to.eq(prevBalance.add(reward));

        //             console.log("");
        //             console.log("<<<<<<<        Auto Rebase Trace      >>>>>>>>")
        //             console.log("total supply: ", currentBalance, prevBalance, reward);
        //             console.log("wallet1: ", curTarget1Balance, prevTarget1Balance, prevTarget1Balance.mul(rewardYield).div(rewardYieldDenominator));
        //             console.log("wallet2: ", curTarget2Balance, prevTarget2Balance, prevTarget2Balance.mul(rewardYield).div(rewardYieldDenominator));

        //         }
        //         await sleep(400); 
        //     }
        // })

        it("auto LP system(every 48 hours)", async() => {
            await swello.approve(router.address, MaxUint256)
            await router.addLiquidityETH(
                swello.address,
                swelloAmount,
                swelloAmount,
                ETHAmount,
                owner.address,
                MaxUint256,
                { ...overrides, value: ETHAmount }
            )

            let curTime = await swello.currentTimestamp();
            await swello.setNextAutoLP(curTime);

            /// every 2 sec for testing
            await swello.setAutoLPFrequency(2);

            const swapETHAmounts = [
                "4278783429253432543",
                "4328743274354354354",
                "3429872394734243244",
                "3242984743943243244",
                "9049284043243243248",
            ]

            const swapSwelloAmounts = [
                "427878342943228888888",
                "432874343243244322743",
                "342434324324432244347",
                "323213213244429847439",
                "321443243242343243248",
            ]

            for(let i = 0; i < 10; i ++) {
                const prevLiquidityReceiverBalance = await WETHPair.balanceOf(liquidityReceiver.address);
                const prevTreasuryReceiverBalance = await ethers.provider.getBalance(treasuryReceiver.address);
                const prevSafetyFundReceiverBalance = await ethers.provider.getBalance(safetyFundReceiver.address);
                const prevCharityReceiverBalance = await ethers.provider.getBalance(charityReceiver.address);
                const prevBurnReceiverBalance = await swello.balanceOf("0x000000000000000000000000000000000000dEaD");

                let xWallet = wallet[i % 9];
                let tx;
                if(i % 2 == 0) {
                    tx = await router.connect(xWallet).swapExactETHForTokens(0, [WETH.address, swello.address], xWallet.address, MaxUint256, {
                        ...overrides,
                        value: BigNumber.from(swapETHAmounts[i >> 1])
                    })
                } else {
                    await swello.connect(xWallet).approve(router.address, MaxUint256)
                    tx = await router.connect(xWallet).swapExactTokensForETHSupportingFeeOnTransferTokens(
                        BigNumber.from(swapSwelloAmounts[i >> 1]),
                        0,
                        [swello.address, WETH.address],
                        xWallet.address,
                        MaxUint256,
                        overrides
                    );
                }

                let receipt = await tx.wait();
                let swapBacked = false;
                let swapBackData = [];
                receipt.events.forEach((x) => {
                    if(x.address == swello.address && x.topics[0] == "0xfc18969df35ccba802c14035d6d6273bf5bb4d8b9de8faa7aba1044c813b1300") {
                        swapBacked = true;
                        let data = x.data.slice(2);
                        for(let j = 0; j < 6; j++) {
                            let amount = data.slice(0, 64);
                            amount = "0x" +  amount;
                            amount = BigNumber.from(amount);
                            swapBackData.push(amount);
                            data = data.slice(64);
                        }
                    }
                })
                if(swapBacked) {
                    console.log("");
                    console.log("<<<<<<<        Auto SwapBack Trace      >>>>>>>>")
                    const [contractBalance, amountToLiquify, amountToSafetyFund, amountToTreasury, amountToBurn, amountToCharity] = swapBackData;
                    const curLiquidityReceiverBalance = await WETHPair.balanceOf(liquidityReceiver.address);
                    const curTreasuryReceiverBalance = await ethers.provider.getBalance(treasuryReceiver.address);
                    const curSafetyFundReceiverBalance = await ethers.provider.getBalance(safetyFundReceiver.address);
                    const curCharityReceiverBalance = await ethers.provider.getBalance(charityReceiver.address);
                    const curBurnReceiverBalance = await swello.balanceOf("0x000000000000000000000000000000000000dEaD");
                    console.log("totalFeeAmount(Swello): ", contractBalance);
                    console.log("liquify(LP token): ", curLiquidityReceiverBalance, prevLiquidityReceiverBalance, amountToLiquify);
                    console.log("safetyfund(BNB): ",curSafetyFundReceiverBalance, prevSafetyFundReceiverBalance, amountToSafetyFund)
                    console.log("treasury(BNB): ", curTreasuryReceiverBalance, prevTreasuryReceiverBalance, amountToTreasury)
                    console.log("burn(Swello): ", curBurnReceiverBalance, prevBurnReceiverBalance, amountToBurn)
                    console.log("charity(BNB): ", curCharityReceiverBalance, prevCharityReceiverBalance, amountToCharity)
                }
                await sleep(400);
            }
        })
    });
})