pub contract OmniverseProtocol {
    pub let FlowChainID: String;
    pub let black_hole_pk: [UInt8];

    // key is generated by `String.encodeHex(publicKey: [UInt8])`
    priv let transactionRecorder: {String: RecordedCertificate};

    // Store pending tokens
    priv let TokenShelter: @{String: [{OmniverseProtocol.OmniverseTokenOperation}]};

    // Store NFTs ready to out, this is the only place to change `OmniverseNFT.NFT` to source `NonFungibleToken.NFT` on Flow
    priv let StarPort: @{String: [{OmniverseProtocol.OmniverseTokenOperation}]};

    // Store punishment NFTs
    priv let Prisons: @{String: [{OmniverseProtocol.OmniverseTokenOperation}]};

    pub let lockPeriod: UFix64;

    pub let CollectionPathPrefix: String
    pub let VaultPathPrefix: String

    pub let SubmitterStoragePath: StoragePath
    pub let SubmitterPublicPath: PublicPath

    pub resource interface OmniverseTokenOperation {
        access(account) var lockedTime: UFix64;

        access(account) fun setLockedTime() {
            post {
                self.lockedTime == getCurrentBlock().timestamp: 
                    panic("set locked time error!");
            }
        }

        pub fun getLockedTime(): UFix64;

        pub fun omniverseTransfer(txSubmitter: Address);
        pub fun omniverseApproveOut(txSubmitter: Address);
        pub fun omniverseTransferIn(txSubmitter: Address);

    }

    pub resource interface OmniverseNFTOperation {
        access(account) fun extract(): @AnyResource{OmniverseNFTOperation};
        access(account) fun omniverseSettle(omniToken: @AnyResource{OmniverseNFTOperation});
    }

    pub resource interface OmniverseFungibleOperation {
        access(account) fun omniverseSettle(omniToken: @AnyResource{OmniverseFungibleOperation});
    }

    pub struct interface OmniverseTokenProtocol {
        pub let nonce: UInt128;

        pub let chainid: String;
        // `contractName` is combined whit `${address} + '.' + ${contract name}`
        pub let contractName: String;

        pub let sender: [UInt8]?;
        pub let recver: [UInt8]?;
        // 0: Omniverse Transfer in(like deposit)
        // 1: Omniverse Transfer
        // 2: Omniverse Approve out(like withdraw)
        pub let operation: UInt8;

        pub fun toBytesExceptNonce(): [UInt8];
        pub fun toBytes(): [UInt8];
        pub fun getOperateIdentity(): [UInt8]; /*{
            pre {
                
                ((self.operation == 0) && (self.recver != nil)) || 
                ((self.operation == 1) && (self.sender != nil)) ||
                ((self.operation == 2) && (self.sender != nil)) : 
                    panic("Invalid operation! Got: ".concat(self.operation.toString()))
                
            } 
        }*/

        // @notice: Non-Fungible Token returns id, which is the `uuid` of wrapped resource `@{NonFungibleToken.INFT}`
        // @notice: Fungible Token returns amount
        pub fun getOmniMeta(): AnyStruct;
    }

    pub struct OmniverseTx {
        pub let txData: AnyStruct{OmniverseTokenProtocol};
        pub let signature: [UInt8];
        pub let timestamp: UFix64;

        pub let hash: String;

        // uuid of the omniverse token resource
        pub let token_uuid: UInt64?;

        init(txData: {OmniverseTokenProtocol}, signature: [UInt8], uuid: UInt64?) {
            self.txData = txData;
            self.signature = signature;
            self.timestamp = getCurrentBlock().timestamp;
            
            self.hash = String.encodeHex(HashAlgorithm.KECCAK_256.hash(self.txData.toBytes()));

            self.token_uuid = uuid;
        }

        pub fun txHash(): String {
            return self.hash;
        }
    }

    pub struct RecordedCertificate {
        priv var nonce: UInt128;
        pub let addressOnFlow: Address;
        // The index of array `PublishedTokenTx` is related nonce,
        // that is, the nonce of a `PublishedTokenTx` instance is its index in the array
        pub let publishedTx: [OmniverseTx];
        
        pub let evil: {UInt128: [OmniverseTx]};

        init(addressOnFlow: Address) {
            self.nonce = 0;
            self.addressOnFlow = addressOnFlow;
            self.publishedTx = [];
            self.evil = {};
        }

        pub fun validCheck() {
            if self.isMalicious() {
                panic("Account: ".concat(self.addressOnFlow.toString()).concat(" has been locked as malicious things!"));
            }
        }

        pub fun getWorkingNonce(): UInt128 {
            return self.nonce + 1;
        }

        access(account) fun makeNextNonce() {
            self.validCheck();

            if self.nonce == UInt128.max {
                self.nonce = 0;
            } else {
                self.nonce = self.nonce + 1;
            }
        }

        access(account) fun addTx(tx: OmniverseTx) {
            self.validCheck();

            if tx.txData.nonce != UInt128(self.publishedTx.length) {
                panic("Nonce error in transaction list! Address: ".concat(self.addressOnFlow.toString()));
            }

            self.publishedTx.append(tx);
        }

        pub fun getAllTx(): [OmniverseTx] {
            return self.publishedTx;
        }

        pub fun getLatestTx(): OmniverseTx? {
            let len = self.publishedTx.length;
            if len > 0 {
                return self.publishedTx[len - 1];
            } else if len == 0 {
                return nil;
            } else {
                panic("Invalid length");
            }
            return nil;
        }

        pub fun getLatestTime(): UFix64 {
            if let latestTx = self.getLatestTx() {
                return latestTx.timestamp;
            } else {
                return 0.0;
            }
        }

        access(account) fun setMalicious(historyTx: OmniverseTx, currentTx: OmniverseTx) {
            if let evilRecord = (&self.evil[historyTx.txData.nonce] as &[OmniverseTx]?) {
                evilRecord.append(currentTx);
            } else {
                self.evil[historyTx.txData.nonce] = [historyTx, currentTx];
            }
        }

        pub fun getEvils(): {UInt128: [OmniverseTx]}{
            return self.evil;
        }

        pub fun isMalicious(): Bool {
            return self.evil.length > 0;
        }
    }

    pub struct Submittion {
        pub let txData: AnyStruct{OmniverseTokenProtocol};
        pub let signature: [UInt8];

        init(txData: AnyStruct{OmniverseTokenProtocol}, signature: [UInt8]) {
            self.txData = txData;
            self.signature = signature;
        }
    }

    pub resource interface SubmitPublic {
        pub fun getSubmittion(): Submittion;
    }

    pub resource TxSubmitter: SubmitPublic {
        priv var submittion: Submittion?;

        init() {
            self.submittion = nil;
        }

        pub fun setSubmittion(submittion: Submittion) {
            self.submittion = submittion;
        }

        pub fun clearSubmittion() {
            self.submittion = nil;
        }

        pub fun getSubmittion(): Submittion {
            return self.submittion!;
        }
    }

    init() {
        self.FlowChainID = "flow-testnet";

        self.black_hole_pk = [UInt8(0)];

        self.transactionRecorder = {};
        self.TokenShelter <- {};
        self.StarPort <- {};
        self.Prisons <- {};

        self.CollectionPathPrefix = "omniverseCollection";
        self.VaultPathPrefix = "omniverseVault";
        self.SubmitterStoragePath = /storage/SubmitterPath;
        self.SubmitterPublicPath = /public/SubmitterPath;

        self.lockPeriod = 10.0 * 60.0;
    }

    pub fun getOmniversePublicCollection(addr: Address, contractName: String): &{OmniverseNFTOperation} {
        let publicPath = PublicPath(identifier: OmniverseProtocol.CollectionPathPrefix.concat(contractName))!;
        let pubAcct = getAccount(addr);
        let cpRef = pubAcct.getCapability<&{OmniverseNFTOperation}>(publicPath).borrow()!;
        return cpRef;
    }

    pub fun getOmniversePublicVault(addr: Address, contractName: String): &{OmniverseFungibleOperation} {
        let publicPath = PublicPath(identifier: OmniverseProtocol.VaultPathPrefix.concat(contractName))!;
        let pubAcct = getAccount(addr);
        let vpRef = pubAcct.getCapability<&{OmniverseFungibleOperation}>(publicPath).borrow()!;
        return vpRef;
    }

    pub fun getSubmitterPublic(addr: Address): &{SubmitPublic} {
        let pubAcct = getAccount(addr);
        let submitterRef = pubAcct.getCapability<&{SubmitPublic}>(OmniverseProtocol.SubmitterPublicPath).borrow()!;
        return submitterRef;
    }

    /////////////////////////////////////////////////////////////////////////////////////////////
    // Core functions
    access(account) fun addOmniverseTx(pubAddr: Address, omniverseTx: OmniverseTx) {
        // Note that remember to check the pk of `pubAddr` is equal to operatorIdentity of `omniverseTx`
        // before call `addOmniverseTx`

        let pkStr = String.encodeHex(omniverseTx.txData.getOperateIdentity());
        if let rc = (&self.transactionRecorder[pkStr] as &RecordedCertificate?) {
            rc.addTx(tx: omniverseTx);            
        } else {
            let rc = RecordedCertificate(addressOnFlow: pubAddr);
            rc.addTx(tx: omniverseTx); 
            self.transactionRecorder[pkStr] = rc;
        }
    }

    access(account) fun addPendingToken(recvIdentity: [UInt8], token: @{OmniverseTokenOperation}) {
        token.setLockedTime();
        let recvStr = String.encodeHex(recvIdentity);
        if let shelter = (&self.TokenShelter[recvStr] as &[{OmniverseTokenOperation}]?) {
            shelter.append(<- token);
        } else {
            self.TokenShelter[recvStr] <-! [<-token];
        }
    }

    access(account) fun addExtractToken(recvIdentity: [UInt8], token: @{OmniverseTokenOperation}) {
        token.setLockedTime();
        let recvStr = String.encodeHex(recvIdentity);
        if let starPort = (&self.StarPort[recvStr] as &[{OmniverseTokenOperation}]?) {
            starPort.append(<- token);
        } else {
            self.StarPort[recvStr] <-! [<-token];
        }
    }

    priv fun takeout(id: UInt64, container: &[{OmniverseTokenOperation}]): @{OmniverseTokenOperation}? {
        let count = container.length;
        var idx = 0;
        while idx < count {
            if container[idx].uuid == id {
                return <- container.remove(at: idx);
            }
            
            idx = idx + 1;
        }

        return nil;
    }

    priv fun lockedUpInPrison(tx: OmniverseTx) {
        let recverStr = String.encodeHex(tx.txData.recver!);
        let opStr = String.encodeHex(tx.txData.getOperateIdentity());

        if tx.txData.operation == 2 {
            // history operation is `withdraw`, so NFT is in `StarPort`
            if let container = (&self.StarPort[recverStr] as &[{OmniverseTokenOperation}]?) {
                if let token <- self.takeout(id: tx.token_uuid!, container: container) {
                    if let prisons = (&self.Prisons[opStr] as &[{OmniverseTokenOperation}]?) {
                        prisons.append(<- token);
                    } else {
                        self.Prisons[opStr] <-! [<- token];
                    }
                }
            }
        } else if tx.txData.operation == 1 {
            // history operation is `transfer`, so NFT is in `NFTShelter`
            if let container = (&self.TokenShelter[recverStr] as &[{OmniverseTokenOperation}]?) {
                if let token <- self.takeout(id: tx.token_uuid!, container: container) {
                    if let prisons = (&self.Prisons[opStr] as &[{OmniverseTokenOperation}]?) {
                        prisons.append(<- token);
                    } else {
                        self.Prisons[opStr] <-! [<- token];
                    }
                }
            }
        }
    }

    // If there's no conflicts, returns true
    access(account) fun checkConflict(tx: OmniverseTx): Bool {
        let rawData = tx.txData.nonce.toBigEndianBytes().concat(tx.txData.toBytesExceptNonce());
        let opIdentity = tx.txData.getOperateIdentity();
        if !OmniverseProtocol.rawVerify(pubKey: opIdentity, 
                                    rawData: rawData, 
                                    signature: tx.signature, 
                                    hashAlgorithm: HashAlgorithm.KECCAK_256) {
            panic("Unauthority Data!");
        }

        let opStr = String.encodeHex(opIdentity);
        if let rc = (&self.transactionRecorder[opStr] as &OmniverseProtocol.RecordedCertificate?) {
            let historyTx = rc.publishedTx[tx.txData.nonce];
            if historyTx.txData.nonce != tx.txData.nonce {
                panic("Nonce-index mechanism failed!");
            }

            if historyTx.hash != tx.hash {
                rc.setMalicious(historyTx: historyTx, currentTx: tx);
                // take the NFT into prisons
                // let recverIdentity = historyTx.txData.recver!;
                self.lockedUpInPrison(tx: historyTx);

                //////////////////////////////////////////////////////////
                // TODO: reward off-chain nodes as they found confilicts
                //////////////////////////////////////////////////////////

                return false;
            } else {
                return true;
            }
        }

        panic("Nonce mechanism crushed at identity: ".concat(opStr));
    }

    // Verify whether both the `pubAddr` and `rawData` are valid
    // `pubAddr` is the address of the message submitter, e.g. the off-chain router
    // So the `signature` is composited with: `pubAddr` + `self.nonce` + `rawData`
    access(account) fun omniverseVerify(pubAddr: Address, rawData: [UInt8], signature: [UInt8], hashAlgorithm: HashAlgorithm): Bool {
        let pubKey = self.getPublicKey(address: pubAddr, signatureAlgorithm: SignatureAlgorithm.ECDSA_secp256k1);
        let pkStr = String.encodeHex(pubKey.publicKey);
        
        var nonceV: UInt128 = 0;
        if let rc = self.transactionRecorder[pkStr] {
            nonceV = rc.getWorkingNonce();
        }
        
        let originData: [UInt8] = nonceV.toBigEndianBytes().concat(rawData);
        //log(String.encodeHex(rawData));
        //log(String.encodeHex(originData));
        //log(pubAddr);
        //log(String.encodeHex(pubAcct.keys.get(keyIndex: 0)!.publicKey.publicKey));
        //log(String.encodeHex(signature));

        if (pubKey.verify(signature: signature,
                        signedData: originData,
                        domainSeparationTag: "",
                        hashAlgorithm: hashAlgorithm)) {
            
            if let rc = (&self.transactionRecorder[pkStr] as &RecordedCertificate?) {
                rc.makeNextNonce();
            } else {
                let rc = RecordedCertificate(addressOnFlow: pubAddr);
                self.transactionRecorder[pkStr] = rc;
            }

            return true;
        } else {
            return false;
        }
    }

    // signature verification without nonce update
    pub fun rawVerify(pubKey: [UInt8], rawData: [UInt8], signature: [UInt8], hashAlgorithm: HashAlgorithm): Bool {        
        let pk = PublicKey(publicKey: pubKey, 
                            signatureAlgorithm: SignatureAlgorithm.ECDSA_secp256k1);

        return pk.verify(signature: signature,
                        signedData: rawData,
                        domainSeparationTag: "",
                        hashAlgorithm: hashAlgorithm);
    }

    /////////////////////////////////////////////////////////////////////////////////////////////
    pub fun getPublicKey(address: Address, signatureAlgorithm: SignatureAlgorithm): PublicKey {
        let pubAcct = getAccount(address);
        let pk = PublicKey(publicKey: pubAcct.keys.get(keyIndex: 0)!.publicKey.publicKey, 
                            signatureAlgorithm: signatureAlgorithm);
        return pk;
    }

    pub fun activeOmniverse(addressOnFlow: Address) {
        let pk = self.getPublicKey(address: addressOnFlow, signatureAlgorithm: SignatureAlgorithm.ECDSA_secp256k1);
        let pkStr = String.encodeHex(pk.publicKey);

        // check if `addressOnFlow` has valid `OmniverseNFT.Collection`
        // let cpRef = self.getCollectionPublic(addr: addressOnFlow);

        if !self.transactionRecorder.containsKey(pkStr) {
            self.transactionRecorder[pkStr] = OmniverseProtocol.RecordedCertificate(addressOnFlow: addressOnFlow);
        }
    }

    pub fun tokenSettlement(addressOnFlow: Address, contractName: String) {
        self.checkValid(opAddressOnFlow: addressOnFlow);

        // do claim job
        let pk = self.getPublicKey(address: addressOnFlow, signatureAlgorithm: SignatureAlgorithm.ECDSA_secp256k1);
        let pkStr = String.encodeHex(pk.publicKey);
        // check if `addressOnFlow` has valid `OmniverseNFT.Collection`
        //let cpRef = self.getOmniversePublicVault(addr: addressOnFlow);
        // active `addressOnFlow` first
        if !self.transactionRecorder.containsKey(pkStr) {
            self.transactionRecorder[pkStr] = OmniverseProtocol.RecordedCertificate(addressOnFlow: addressOnFlow);
        }
        // claim all pended NFTs under public key `pkStr`
        if let shelter = (&self.TokenShelter[pkStr] as &[AnyResource{OmniverseProtocol.OmniverseTokenOperation}]?) {
            var counts = shelter.length;
            while counts > 0 {
                let idx = shelter.length - 1;
                if (getCurrentBlock().timestamp - shelter[idx].getLockedTime()) > self.lockPeriod {
                    let pendedToken <- shelter.remove(at: idx);
                    if let rawToken <- pendedToken as? @AnyResource{OmniverseFungibleOperation} {
                        let vpRef = self.getOmniversePublicVault(addr: addressOnFlow, contractName: contractName);
                        vpRef.omniverseSettle(omniToken: <- rawToken);

                    } else if let rawToken <- pendedToken as? @AnyResource{OmniverseNFTOperation} {
                        let cpRef = self.getOmniversePublicCollection(addr: addressOnFlow, contractName: contractName);
                        cpRef.omniverseSettle(omniToken: <- rawToken);

                    } else {
                        destroy pendedToken;
                    }
                }

                counts = counts - 1;
            }
        }
    }

    pub fun checkValid(opAddressOnFlow: Address): Bool {
        let pk = self.getPublicKey(address: opAddressOnFlow, signatureAlgorithm: SignatureAlgorithm.ECDSA_secp256k1);
        let pkStr = String.encodeHex(pk.publicKey);

        if let rc = (&self.transactionRecorder[pkStr] as &RecordedCertificate?) {
            if rc.isMalicious() {
                panic("The address did malicious things and has been locked now!");
            }
        }

        return true;
    }

    pub fun getOmniverseIdentity(pubAddr: Address): [UInt8] {
        let pubKey = self.getPublicKey(address: pubAddr, signatureAlgorithm: SignatureAlgorithm.ECDSA_secp256k1);
        return pubKey.publicKey;
    }

    pub fun getFlowAddress(pubKey: [UInt8]): Address? {
        let pkStr = String.encodeHex(pubKey);
        if let rc = self.transactionRecorder[pkStr] {
            return rc.addressOnFlow;
        }

        return nil;
    }

    pub fun getWorkingNonce(pubAddr: Address): UInt128 {
        let pubKey = self.getPublicKey(address: pubAddr, signatureAlgorithm: SignatureAlgorithm.ECDSA_secp256k1);
        let pkStr = String.encodeHex(pubKey.publicKey);
        if let rc = self.transactionRecorder[pkStr] {
            return rc.getWorkingNonce();
        } else {
            return 0;
        }
    }

    pub fun getLatestTxTime(pubKey: [UInt8]): UFix64 {
        let pkStr = String.encodeHex(pubKey);
        if let rc = self.transactionRecorder[pkStr] {
            return rc.getLatestTime();
        }

        return 0.0;
    }

    // for test and human check

}
 