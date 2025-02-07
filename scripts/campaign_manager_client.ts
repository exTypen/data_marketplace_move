import { AptosClient, AptosAccount, FaucetClient, Types, HexString } from "aptos";
import * as dotenv from "dotenv";

const NODE_URL = "https://fullnode.devnet.aptoslabs.com";
const FAUCET_URL = "https://faucet.devnet.aptoslabs.com";

interface Campaign {
    id: number;
    creator: string;
    data_spec: string;
    quality_criteria: string;
    reward_pool: number;
    active: boolean;
}

class CampaignManager {
    private client: AptosClient;
    private account: AptosAccount;

    constructor(privateKeyHex: string) {
        this.client = new AptosClient(NODE_URL);
        this.account = new AptosAccount(
            HexString.ensure(privateKeyHex).toUint8Array()
        );
    }

    getAddress(): string {
        return this.account.address().hex();
    }

    async initCampaignStore(): Promise<void> {
        try {
            const initTxn = await this.client.generateTransaction(this.account.address(), {
                function: `${this.account.address()}::CampaignManagerV2::init_campaign_store`,
                type_arguments: [],
                arguments: []
            });
            
            const signedTxn = await this.client.signTransaction(this.account, initTxn);
            const initResult = await this.client.submitTransaction(signedTxn);
            await this.client.waitForTransaction(initResult.hash);
            console.log("Campaign Store başarıyla başlatıldı!");
        } catch (e) {
            console.log("Campaign Store zaten başlatılmış olabilir:", e);
        }
    }

    async createCampaign(
        dataSpec: string,
        qualityCriteria: string,
        rewardPool: number
    ): Promise<void> {
        try {
            const createTxn = await this.client.generateTransaction(this.account.address(), {
                function: `${this.account.address()}::CampaignManagerV2::create_campaign`,
                type_arguments: [],
                arguments: [
                    Array.from(Buffer.from(dataSpec)),
                    Array.from(Buffer.from(qualityCriteria)),
                    rewardPool.toString()
                ]
            });

            const signedCreateTxn = await this.client.signTransaction(this.account, createTxn);
            const createResult = await this.client.submitTransaction(signedCreateTxn);
            await this.client.waitForTransaction(createResult.hash);
            console.log("Yeni kampanya başarıyla oluşturuldu!");
        } catch (e) {
            console.log("Kampanya oluşturma hatası:", e);
            throw e;
        }
    }

    async getCampaign(campaignId: number): Promise<Campaign | null> {
        try {
            const payload: Types.ViewRequest = {
                function: `${this.account.address()}::CampaignManagerV2::get_campaign`,
                type_arguments: [],
                arguments: [campaignId.toString(), this.account.address().hex()]
            };

            const response = await this.client.view(payload);
            return this.parseCampaignResponse(response[0]);
        } catch (e) {
            console.log("Kampanya bilgisi alınamadı:", e);
            return null;
        }
    }

    async listAllCampaigns(): Promise<Campaign[]> {
        try {
            const payload: Types.ViewRequest = {
                function: `${this.account.address()}::CampaignManagerV2::get_all_campaigns`,
                type_arguments: [],
                arguments: [this.account.address().hex()]
            };

            const response = await this.client.view(payload);
            const campaigns = response[0] as any[];
            return campaigns.map(camp => this.parseCampaignResponse(camp));
        } catch (e) {
            console.log("Kampanyalar listelenirken hata oluştu:", e);
            return [];
        }
    }

    private parseCampaignResponse(response: any): Campaign {
        return {
            id: Number(response.id),
            creator: response.creator,
            data_spec: Buffer.from(response.data_spec.slice(2), 'hex').toString(),
            quality_criteria: Buffer.from(response.quality_criteria.slice(2), 'hex').toString(),
            reward_pool: Number(response.reward_pool),
            active: response.active
        };
    }
}

async function main() {
    const privateKeyHex = "0x282124b5e7bf7fbc3515af48b17fb173766f08024481246854abcac02ed60d81";
    const campaignManager = new CampaignManager(privateKeyHex);

    console.log("Hesap adresi:", campaignManager.getAddress());

    // Önce store'u başlat
    //await campaignManager.initCampaignStore();

    // Yeni kampanya oluştur
    
    /*
    await campaignManager.createCampaign(
        "Test Kampanya 1",
        "Kalite Kriterleri 1",
        1000
    );
    */

    // Tüm kampanyaları listele
    const campaigns = await campaignManager.listAllCampaigns();
    console.log("\nToplam kampanya sayısı:", campaigns.length);
    campaigns.forEach(campaign => {
        console.log("\nKampanya Detayları:");
        console.log("ID:", campaign.id);
        console.log("Oluşturan:", campaign.creator);
        console.log("Veri Spesifikasyonu:", campaign.data_spec);
        console.log("Kalite Kriterleri:", campaign.quality_criteria);
        console.log("Ödül Havuzu:", campaign.reward_pool);
        console.log("Aktif mi:", campaign.active);
    });
}

main().catch(console.error);
