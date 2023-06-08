import {FlowService, settlement, sendTransaction, execScripts} from './scaffold-flow/flowoffchain.mjs'
import fcl, { send } from '@onflow/fcl';
import * as types from "@onflow/types";
import { SHA3 } from 'sha3';
import keccak256 from 'keccak256';
import oc from './scaffold-flow/omnichainCrypto.js';
import {opType, OmniverseNFTPayload} from './erc6358types.js';

// import fs from 'fs';
// import path from 'path';

import {program} from 'commander';

const sha3_256FromString = (msg) => {
    const sha = new SHA3(256);
    sha.update(Buffer.from(msg, 'hex'));
    return sha.digest();
};

const fs_owner = new FlowService('0xf8d6e0586b0a20c7', 
                                    '69e7e51ead557351ade7a575e947c4d4bd19dd8a6cdf00c51f9c7f6f721b72dc',
                                    0,
                                    sha3_256FromString,
                                    'secp256k1');

const fsAlice = new FlowService('0x01cf0e2f2f715450', 
                                    'c9193930b34dd498378e36c35118a627d9eb500f6fd69b16d8e59db7cc8f5bb3',
                                    0,
                                    sha3_256FromString,
                                    'secp256k1');

const fsBob = new FlowService('0x179b6b1cb6755e31', 
                                    'd95472318e773b2046b078ae252c42082752c7b7876ce2770a2d3e00b02bbed5',
                                    0,
                                    sha3_256FromString,
                                    'secp256k1');

const fsCarl = new FlowService('0xf3fcd2c1a78f5eee', 
                                    'f559fa403545e328ea024ef27e030a478634ae04212519e8bb5293add4b6dda4',
                                    0,
                                    sha3_256FromString,
                                    'secp256k1');

const fs_map = {
    "owner": fs_owner,
    "Alice": fsAlice,
    "Bob": fsBob,
    "Carl": fsCarl
}

async function setMembers(members) {
    // console.log(members);
    // let fcl_arg = fcl.arg([{key: 1, value: "one"}, {key: 2, value: "two"}], types.Dictionary({key: types.UInt32, value: types.String}));
    let fcl_arg = fcl.arg(JSON.parse(members), types.Dictionary({key: types.UInt32, value: types.String}));

    let response = await sendTransaction({flowService: fs_owner, tx_path: "../transactions/setMembers.cdc", args: [fcl_arg]});

    await settlement(response);
}

async function checkMembers() {
    let rstData = await execScripts({flowService: fs_owner, script_path: "../scripts/getMembers.cdc", args: []});

    console.log(rstData);
}

async function setLockPeriod(period) {
    let fcl_arg = fcl.arg(period, types.UFix64);

    await settlement(await sendTransaction({flowService: fs_owner, tx_path: "../transactions/setLockPeriod.cdc", args: [fcl_arg]}));
}

async function checkLockPeriod() {
    console.log(await execScripts({flowService: fs_owner, script_path: "../scripts/getLockPeriod.cdc", args: []}));
}

async function checkSimuAccounts() {
    const keys = Object.keys(fs_map);
    for (var i in keys) {
        const tempOC = new oc.OmnichainCrypto(keccak256, 'secp256k1', fs_map[keys[i]].signerPrivateKeyHex);
        console.log("Account: " + keys[i]);
        console.log("Public Key: "+ tempOC.getPublic());
        console.log("**********************************");
    }
}

async function sendOmniverseTransaction(from, to, tokenId) {
    
}

async function mint() {
    const ownerOC = new oc.OmnichainCrypto(keccak256, 'secp256k1', fs_owner.signerPrivateKeyHex);

    const nftMeta = await execScripts({
        flowService: fs_owner, 
        script_path: "../scripts/getNFTTxMeta.cdc", 
        args: [
            fcl.arg(Array.from(Buffer.from(ownerOC.getPublic().substring(2), 'hex')).map((item) => {return String(item)}), types.Array(types.UInt8))
        ]
    });
    console.log(nftMeta);

    const oNFTPayload = new OmniverseNFTPayload(opType.o_mint, ownerOC.getPublic().substring(2), nftMeta.nextNFTId, await fcl.config.get('Profile'));

    console.log(oNFTPayload.get_fcl_arg());
}

function list(val) {
    if (val == undefined) {
        return [];
    } else {
        return val.split(',');
    }
}

function list_line(val) {
    return val.split('|');
}

async function commanders() {
    program
        .version('Test Tools for omniverse Flow. v0.0.1')
        .option('--check-accounts', 'Check the simulation accounts')
        .option('--set-members <members>', 'Set the member chains of the Omniverse NFT', list_line)
        .option('--check-members', 'Check the allowed members')
        .option('--set-lock-period <period>', 'Set the cooling time', list_line)
        .option('--check-lock-period', 'Check the cooling time')
        .option('--mint', 'mint an omniverse NFT to the owner account')
        .parse(process.argv);
        
    if (program.opts().setMembers) {
        if (program.opts().setMembers.length != 1) {
            console.log('1 arguments are needed, but ' + program.opts().setMembers.length + ' provided');
            return;
        }

        await setMembers(...program.opts().setMembers);
    } else if (program.opts().checkMembers) {
        await checkMembers();
    } else if (program.opts().setLockPeriod) {
        if (program.opts().setLockPeriod.length != 1) {
            console.log('1 arguments are needed, but ' + program.opts().setLockPeriod.length + ' provided');
            return;
        }

        await setLockPeriod(...program.opts().setLockPeriod);
    } else if (program.opts().checkLockPeriod) {
        await checkLockPeriod();
    } else if (program.opts().checkAccounts) {
        await checkSimuAccounts();
    } else if (program.opts().mint) {
        // if (program.opts().mint.length != 1) {
        //     console.log('1 arguments are needed, but ' + program.opts().mint.length + ' provided');
        //     return;
        // }

        await mint();
    } 
}

await commanders();
