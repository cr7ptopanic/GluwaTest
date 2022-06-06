import { expect } from "chai";
import { describe, it, before } from "mocha";
import { ethers } from "hardhat";
import { Gluwa, Gluwa__factory, DAI__factory } from "../typechain-types";
import { BigNumber } from "ethers";

export async function increaseTime(duration: number) {
  await ethers.provider.send("evm_increaseTime", [duration]);
  await ethers.provider.send("evm_mine", []);
}

describe("Gluwa", () => {
  let gluwa: Gluwa;
  let alice: any;
  let Dai: any;

  before(async () => {
    const DAI = (await ethers.getContractFactory("DAI")) as DAI__factory;
    const Gluwa = (await ethers.getContractFactory("Gluwa")) as Gluwa__factory;

    [, alice] = await ethers.getSigners();

    Dai = await DAI.deploy();

    gluwa = await Gluwa.deploy(Dai.address);

    await Dai.mint(alice.address, 1000);
    await Dai.connect(alice).approve(gluwa.address, 1000);
  });

  describe("Deposit", () => {
    it("Cannot deposit with zero amount", async () => {
      await expect(gluwa.connect(alice).deposit(0, 100, true)).to.revertedWith(
        "GluwaError(0)"
      );
    });

    it("Success Deposit", async () => {
      const prevBalance = await Dai.balanceOf(alice.address);
      const depositAmount = 100;
      await gluwa.connect(alice).deposit(depositAmount, 6048000, false); // No lockup period => maturity: 70 days
      await gluwa.connect(alice).deposit(depositAmount, 31536000, true); // Fixed lockup period => Maturity: 1 year

      expect(await Dai.balanceOf(alice.address)).to.equal(prevBalance - 200);
    });
  });

  describe("Withdraw Rewards", async () => {
    it("Tranche id is zero", async () => {
      await expect(gluwa.connect(alice).withdrawRewards(0)).to.revertedWith(
        "GluwaError(1)"
      );
    });

    it("Tranche id is invalid", async () => {
      await expect(gluwa.connect(alice).withdrawRewards(5)).to.revertedWith(
        "GluwaError(1)"
      );
    });

    it("Not time to withdraw", async () => {
      await expect(gluwa.connect(alice).withdrawRewards(1)).to.revertedWith(
        "GluwaError(2)"
      );
    });

    it("No lock-up withdraw", async () => {
      increaseTime(6048000); // after 70 days
      const reward = BigNumber.from(
        Math.floor(((100 * 6048000) / (365 * 24 * 3600) / 100) * 12)
      );

      await gluwa.connect(alice).withdrawRewards(1);

      expect(await gluwa.balanceOf(alice.address)).to.equal(reward);
    });

    it("Lock-up withdraw", async () => {
      increaseTime(31622400); // after 1 year later
      const reward = ((100 * 31536000) / (365 * 24 * 3600) / 100) * 35;

      await gluwa.connect(alice).withdrawRewards(2);

      expect(await gluwa.balanceOf(alice.address)).to.equal(reward + 2); // 2 => previous no lock-up period rewards
    });
  });

  describe("Withdraw deposited tokens", async () => {
    it("Amount is zero", async () => {
      await expect(
        gluwa.connect(alice).withdrawDepositedTokens(0, 1)
      ).to.revertedWith("GluwaError(0)");
    });

    it("Amount is bigger than deposited amount", async () => {
      await expect(
        gluwa.connect(alice).withdrawDepositedTokens(200, 1)
      ).to.revertedWith("GluwaError(0)");
    });

    it("Tranche id is zero", async () => {
      await expect(
        gluwa.connect(alice).withdrawDepositedTokens(100, 0)
      ).to.revertedWith("GluwaError(1)");
    });

    it("Tranche id is invalid", async () => {
      await expect(
        gluwa.connect(alice).withdrawDepositedTokens(100, 5)
      ).to.revertedWith("GluwaError(1)");
    });

    it("lock-up withdraw before maturity(15% fee)", async () => {
      const depositAmount = 200;
      await gluwa.connect(alice).deposit(depositAmount, 604800, true);

      await gluwa.connect(alice).withdrawDepositedTokens(100, 3);

      expect(await Dai.balanceOf(alice.address)).to.equal(685);
    });

    it("Other withdraw", async () => {
      await gluwa.connect(alice).withdrawDepositedTokens(100, 2);

      expect(await Dai.balanceOf(alice.address)).to.equal(785);
    });
  });

  describe("Swap", async () => {
    it("Amount is zero", async () => {
      await expect(gluwa.connect(alice).swap(0)).to.revertedWith(
        "GluwaError(0)"
      );
    });

    it("Amount is out of range", async () => {
      await expect(gluwa.connect(alice).swap(1000)).to.revertedWith(
        "GluwaError(0)"
      );
    });

    it("Sucess", async () => {
      await gluwa.connect(alice).swap(2);
      expect(await Dai.balanceOf(alice.address)).to.equal(787);
    });
  });
});
