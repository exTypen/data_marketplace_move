import { AptosAccount, TxnBuilderTypes } from "aptos";
import { BCS } from "aptos";
import { sha256 } from "@noble/hashes/sha256";
import dotenv from "dotenv";

dotenv.config();

async function signTestData() {
    // Test verileri
    const campaignId = 1n;
    const dataCount = 1n;
    const storeKey = Buffer.from("test_store_key");
    const score = 100n;

    // Private key'den hesap oluştur
    const account = new AptosAccount(
        Buffer.from(process.env.TRUSTED_PRIVATE_KEY || "", "hex")
    );

    // Manuel serileştirme
    const message = Buffer.alloc(8 + 8 + 8 + storeKey.length + 8); // campaign_id + data_count + store_key_len + store_key + score
    
    // campaign_id (u64)
    message.writeBigUInt64LE(campaignId, 0);
    
    // data_count (u64)
    message.writeBigUInt64LE(dataCount, 8);
    
    // store_key_len (u64)
    message.writeBigUInt64LE(BigInt(storeKey.length), 16);
    
    // store_key (bytes)
    storeKey.copy(message, 24);
    
    // score (u64)
    message.writeBigUInt64LE(score, 24 + storeKey.length);
    
    // Mesajı hash'le (SHA2-256) ve imzala
    const messageHash = sha256(message);
    const signature = account.signBuffer(messageHash).toUint8Array();
    const signatureHex = Buffer.from(signature).toString('hex');
    
    // Move test fonksiyonu için formatlanmış çıktı
    console.log(`let signature: vector<u8> = x"${signatureHex}";`);
}

signTestData().catch(console.error); 