
import Foundation
import secp256k1_ios
import BigInt



struct SECP256K1 {
    struct UnmarshaledSignature{
        var v: UInt8
        var r = [UInt8](repeating: 0, count: 32)
        var s = [UInt8](repeating: 0, count: 32)
    }
    
    static var secp256k1_N  = BigUInt("fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141", radix: 16)!
    static var secp256k1_halfN = secp256k1_N >> 2
}

extension SECP256K1 {
    static var context = secp256k1_context_create(UInt32(SECP256K1_CONTEXT_SIGN|SECP256K1_CONTEXT_VERIFY))
    
    static func signForRecovery(hash: Data, privateKey: Data, useExtraEntropy: Bool = true) -> (serializedSignature:Data?, rawSignature: Data?) {
        if (hash.count != 32 || privateKey.count != 32) {return (nil, nil)}
        if !SECP256K1.verifyPrivateKey(privateKey: privateKey) {
            return (nil, nil)
        }
        for rounds in 0...1024 {
            guard var recoverableSignature = SECP256K1.recoverableSign(hash: hash, privateKey: privateKey, useExtraEntropy: useExtraEntropy) else {
                continue
            }
            guard let truePublicKey = SECP256K1.privateKeyToPublicKey(privateKey: privateKey) else {continue}
            guard let recoveredPublicKey = SECP256K1.recoverPublicKey(hash: hash, recoverableSignature: &recoverableSignature) else {continue}
            if Data(toByteArray(truePublicKey.data)) != Data(toByteArray(recoveredPublicKey.data)) {
                print("Didn't recover correctly!")
                continue
            }
            guard let serializedSignature = SECP256K1.serializeSignature(recoverableSignature: &recoverableSignature) else {continue}
            let rawSignature = Data(toByteArray(recoverableSignature))
            return (serializedSignature, rawSignature)
            print("Signature required \(rounds) rounds")
        }
        print("Signature required 1024 rounds and failed")
        return (nil, nil)
    }
    
    static func privateToPublic(privateKey: Data, compressed: Bool = false) -> Data? {
        if (privateKey.count != 32) {return nil}
        guard var publicKey = SECP256K1.privateKeyToPublicKey(privateKey: privateKey) else {return nil}
        guard let serializedKey = serializePublicKey(publicKey: &publicKey, compressed: compressed) else {return nil}
        return serializedKey
    }
    
    static func combineSerializedPublicKeys(keys: [Data], outputCompressed: Bool = false) -> Data? {
        let numToCombine = keys.count
        guard numToCombine >= 1 else { return nil}
        var publicKeys = [UnsafePointer<secp256k1_pubkey>?]()
        var result:Int32
        for i in 0..<numToCombine {
            var publicKey = secp256k1_pubkey()
            let key = keys[i]
            let keyLen = key.count
            result = key.withUnsafeBytes { (publicKeyPointer:UnsafePointer<UInt8>) -> Int32 in
                let res = secp256k1_ec_pubkey_parse(context!, UnsafeMutablePointer<secp256k1_pubkey>(&publicKey), publicKeyPointer, keyLen)
                return res
            }
            if result == 0 {
                return nil
            }
            let pointer = UnsafePointer<secp256k1_pubkey>(UnsafeMutablePointer<secp256k1_pubkey>(&publicKey))
            publicKeys.append(pointer)
        }
        
        var publicKey: secp256k1_pubkey = secp256k1_pubkey()
        let arrayPointer = UnsafePointer(publicKeys)
        result = secp256k1_ec_pubkey_combine(context!, UnsafeMutablePointer<secp256k1_pubkey>(&publicKey), arrayPointer, numToCombine)
        if result == 0 {
            return nil
        }
        
        var keyLength = outputCompressed ? 33 : 65
        var serializedPubkey = Data(repeating: 0x00, count: keyLength)
        
        result = serializedPubkey.withUnsafeMutableBytes { (serializedPubkeyPointer:UnsafeMutablePointer<UInt8>) -> Int32 in
            let res = secp256k1_ec_pubkey_serialize(context!,
                                                    serializedPubkeyPointer,
                                                    UnsafeMutablePointer<Int>(&keyLength),
                                                    UnsafeMutablePointer<secp256k1_pubkey>(&publicKey),
                                                    UInt32(outputCompressed ? SECP256K1_EC_COMPRESSED : SECP256K1_EC_UNCOMPRESSED))
            return res
        }
        return Data(serializedPubkey)
    }
    
    static func recoverPublicKey(hash: Data, recoverableSignature: inout secp256k1_ecdsa_recoverable_signature) -> secp256k1_pubkey? {
        guard hash.count == 32 else {return nil}
        var publicKey: secp256k1_pubkey = secp256k1_pubkey()
        let result = hash.withUnsafeBytes { (hashPointer:UnsafePointer<UInt8>) -> Int32 in
            withUnsafePointer(to: &recoverableSignature, { (signaturePointer:UnsafePointer<secp256k1_ecdsa_recoverable_signature>) -> Int32 in
                withUnsafeMutablePointer(to: &publicKey, { (pubKeyPtr: UnsafeMutablePointer<secp256k1_pubkey>) -> Int32 in
                    let res = secp256k1_ecdsa_recover(context!, pubKeyPtr,
                                                      signaturePointer, hashPointer)
                    return res
                })
            })
        }
        if result == 0 {
            return nil
        }
        return publicKey
    }
    
    static func privateKeyToPublicKey(privateKey: Data) -> secp256k1_pubkey? {
        if (privateKey.count != 32) {return nil}
        var publicKey = secp256k1_pubkey()
        let result = privateKey.withUnsafeBytes { (privateKeyPointer:UnsafePointer<UInt8>) -> Int32 in
            let res = secp256k1_ec_pubkey_create(context!, UnsafeMutablePointer<secp256k1_pubkey>(&publicKey), privateKeyPointer)
            return res
        }
        if result == 0 {
            return nil
        }
        return publicKey
    }
    
    static func serializePublicKey(publicKey: inout secp256k1_pubkey, compressed: Bool = false) -> Data? {
        var keyLength = compressed ? 33 : 65
        var serializedPubkey = Data(repeating: 0x00, count: keyLength)
        let result = serializedPubkey.withUnsafeMutableBytes { (serializedPubkeyPointer:UnsafeMutablePointer<UInt8>) -> Int32 in
            withUnsafeMutablePointer(to: &keyLength, { (keyPtr:UnsafeMutablePointer<Int>) -> Int32 in
                withUnsafeMutablePointer(to: &publicKey, { (pubKeyPtr:UnsafeMutablePointer<secp256k1_pubkey>) -> Int32 in
                    let res = secp256k1_ec_pubkey_serialize(context!,
                                                            serializedPubkeyPointer,
                                                            keyPtr,
                                                            pubKeyPtr,
                                                            UInt32(compressed ? SECP256K1_EC_COMPRESSED : SECP256K1_EC_UNCOMPRESSED))
                    return res
                })
            })
        }
        
        if result == 0 {
            return nil
        }
        return Data(serializedPubkey)
    }
    
    static func parsePublicKey(serializedKey: Data) -> secp256k1_pubkey? {
        guard serializedKey.count == 33 || serializedKey.count == 65 else {
            return nil
        }
        let keyLen: Int = Int(serializedKey.count)
        var publicKey = secp256k1_pubkey()
        let result = serializedKey.withUnsafeBytes { (serializedKeyPointer:UnsafePointer<UInt8>) -> Int32 in
            let res = secp256k1_ec_pubkey_parse(context!, UnsafeMutablePointer<secp256k1_pubkey>(&publicKey), serializedKeyPointer, keyLen)
            return res
            }
        if result == 0 {
            return nil
        }
        return publicKey
    }
    
    static func parseSignature(signature: Data) -> secp256k1_ecdsa_recoverable_signature? {
         guard signature.count == 65 else {return nil}
        var recoverableSignature: secp256k1_ecdsa_recoverable_signature = secp256k1_ecdsa_recoverable_signature()
        let serializedSignature = Data(signature[0..<64])
        let v = Int32(signature[64])
        let result = serializedSignature.withUnsafeBytes{ (serPtr: UnsafePointer<UInt8>) -> Int32 in
            withUnsafeMutablePointer(to: &recoverableSignature, { (signaturePointer:UnsafeMutablePointer<secp256k1_ecdsa_recoverable_signature>) -> Int32 in
                    let res = secp256k1_ecdsa_recoverable_signature_parse_compact(context!, signaturePointer, serPtr, v)
                    return res
            })
        }
        if result == 0 {
            return nil
        }
        return recoverableSignature
    }
    
    static func serializeSignature(recoverableSignature: inout secp256k1_ecdsa_recoverable_signature) -> Data? {
        var serializedSignature = Data(repeating: 0x00, count: 64)
        var v: Int32 = 0
        let result = serializedSignature.withUnsafeMutableBytes { (serSignaturePointer:UnsafeMutablePointer<UInt8>) -> Int32 in
            withUnsafePointer(to: &recoverableSignature) { (signaturePointer:UnsafePointer<secp256k1_ecdsa_recoverable_signature>) -> Int32 in
                withUnsafeMutablePointer(to: &v, { (vPtr: UnsafeMutablePointer<Int32>) -> Int32 in
                    let res = secp256k1_ecdsa_recoverable_signature_serialize_compact(context!, serSignaturePointer, vPtr, signaturePointer)
                    return res
                })
            }
        }
        if result == 0 {
            return nil
        }
        if (v == 0) {
            serializedSignature.append(0x00)
        } else if (v == 1) {
            serializedSignature.append(0x01)
        } else {
            return nil
        }
        return Data(serializedSignature)
    }
    
    static func recoverableSign(hash: Data, privateKey: Data, useExtraEntropy: Bool = true) -> secp256k1_ecdsa_recoverable_signature? {
        if (hash.count != 32 || privateKey.count != 32) {
            return nil
        }
        if !SECP256K1.verifyPrivateKey(privateKey: privateKey) {
            return nil
        }
        var recoverableSignature: secp256k1_ecdsa_recoverable_signature = secp256k1_ecdsa_recoverable_signature();
        guard let extraEntropy = Data.randomBytes(length: 32) else {return nil}
        let result = hash.withUnsafeBytes { (hashPointer:UnsafePointer<UInt8>) -> Int32 in
            privateKey.withUnsafeBytes { (privateKeyPointer:UnsafePointer<UInt8>) -> Int32 in
                extraEntropy.withUnsafeBytes { (extraEntropyPointer:UnsafePointer<UInt8>) -> Int32 in
                    withUnsafeMutablePointer(to: &recoverableSignature, { (recSignaturePtr: UnsafeMutablePointer<secp256k1_ecdsa_recoverable_signature>) -> Int32 in
                            let res = secp256k1_ecdsa_sign_recoverable(context!, recSignaturePtr, hashPointer, privateKeyPointer, nil, useExtraEntropy ? extraEntropyPointer : nil)
                            return res
                        })
                }
            }
        }
        if result == 0 {
            print("Failed to sign!")
            return nil
        }
        return recoverableSignature
    }
    
    static func recoverPublicKey(hash: Data, signature: Data, compressed: Bool = false) -> Data? {
        guard hash.count == 32, signature.count == 65 else {return nil}
        guard var recoverableSignature = parseSignature(signature: signature) else {return nil}
        guard var publicKey = SECP256K1.recoverPublicKey(hash: hash, recoverableSignature: &recoverableSignature) else {return nil}
        guard let serializedKey = SECP256K1.serializePublicKey(publicKey: &publicKey, compressed: compressed) else {return nil}
        return serializedKey
    }
    
    static func recoverSender(hash: Data, signature: Data) -> EthereumAddress? {
        guard let pubKey = SECP256K1.recoverPublicKey(hash:hash, signature:signature, compressed: false) else {return nil}
        guard pubKey.count == 65 else {return nil}
        let addressData = Data(pubKey.sha3(.keccak256)[12..<32])
        return EthereumAddress(addressData)
    }
    
    static func verifyPrivateKey(privateKey: Data) -> Bool {
        if (privateKey.count != 32) {return false}
        let result = privateKey.withUnsafeBytes { (privateKeyPointer:UnsafePointer<UInt8>) -> Int32 in
            let res = secp256k1_ec_seckey_verify(context!, privateKeyPointer)
            return res
        }
        return result == 1
    }
    
    static func generatePrivateKey() -> Data? {
        for _ in 0...1024 {
            guard let keyData = Data.randomBytes(length: 32) else {
                continue
            }
            return keyData
        }
        return nil
    }
    
    static func unmarshalSignature(signatureData:Data) -> UnmarshaledSignature? {
        if (signatureData.count != 65) {return nil}
        let bytes = signatureData.bytes
        let r = Array(bytes[0..<32])
        let s = Array(bytes[32..<64])
        return UnmarshaledSignature(v: bytes[64], r: r, s: s)
    }
    
    static func marshalSignature(v: UInt8, r: [UInt8], s: [UInt8]) -> Data? {
        guard r.count == 32, s.count == 32 else {return nil}
        var completeSignature = Data(bytes: r)
        completeSignature.append(Data(bytes: s))
        completeSignature.append(Data(bytes: [v]))
        return completeSignature
    }
    
    static func marshalSignature(v: Data, r: Data, s: Data) -> Data? {
        guard r.count == 32, s.count == 32 else {return nil}
        var completeSignature = Data(r)
        completeSignature.append(s)
        completeSignature.append(v)
        return completeSignature
    }
}






