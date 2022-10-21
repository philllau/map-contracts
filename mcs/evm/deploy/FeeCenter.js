

module.exports = async function ({ethers, deployments}) {
    const {deploy} = deployments
    const {deployer} = await ethers.getNamedSigners()

    console.log("deployer address:",deployer.address);

    await deploy('FeeCenter', {
        from: deployer.address,
        args: [],
        log: true,
        contract: 'FeeCenter',
    })

    let feeCenter = await ethers.getContract('FeeCenter');

    console.log("feeCenter address:",feeCenter.address);

}

module.exports.tags = ['FeeCenter']