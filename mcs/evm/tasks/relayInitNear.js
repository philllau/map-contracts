
module.exports = async (taskArgs,hre) => {
    const accounts = await ethers.getSigners()
    const deployer = accounts[0];

    console.log("deployer address:",deployer.address);

    let proxy = await hre.deployments.get("MAPCrossChainServiceRelayProxy")

    let mosRelayProxy = await ethers.getContractAt('MAPCrossChainServiceRelay',proxy.address);

    await (await mosRelayProxy.connect(deployer).setChain(taskArgs.name,taskArgs.chain)).wait();

    console.log(`MAPCrossChainServiceRelay init near chain success`);

}