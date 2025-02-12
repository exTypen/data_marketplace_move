import { AptosClient, AptosAccount, FaucetClient, Types, HexString } from "aptos";
import * as dotenv from 'dotenv';
import { DataSigner } from './sign_test_data';

dotenv.config();

// Sabitler
const CONFIG = {
    NODE_URL: process.env.NODE_URL || "https://fullnode.devnet.aptoslabs.com",
    FAUCET_URL: process.env.FAUCET_URL || "https://faucet.devnet.aptoslabs.com",
    MODULE_ADDRESS: process.env.MODULE_ADDRESS || "0x027a1f3f1eb58353c3bdb92b69ce9e4c37ca77cbc7a2a1b54158f2729e957129"
};

// Interfaces
interface Campaign {
    id: number;
    creator: string;
    title: string;
    description: string;
    prompt: string;
    reward_pool: number;
    remaining_reward: number;
    unit_price: number;
    minimum_contribution: number;
    active: boolean;
}

interface Contribution {
    campaign_id: number;
    contributor: string;
    data_count: number;
    store_cid: string;
    score: number;
    signature: string;
}

interface AccountBalance {
    amount: number;
    decimals: number;
    formatted: string;
}

// Utility Functions
class AptosUtils {
    static stringToBytes(str: string): number[] {
        return Array.from(Buffer.from(str));
    }

    static bytesToString(bytes: number[]): string {
        return Buffer.from(bytes).toString();
    }

    static hexToBytes(hex: string): number[] {
        return Array.from(Buffer.from(hex.startsWith('0x') ? hex.slice(2) : hex, 'hex'));
    }

    static formatBalance(amount: number, decimals: number = 8): string {
        return (amount / Math.pow(10, decimals)).toFixed(decimals);
    }

    static createEntryPayload(func: string, args: any[]): Types.EntryFunctionPayload {
        return {
            function: func,
            type_arguments: [],
            arguments: args
        };
    }
}

// Base Manager Class
class BaseManager {
    protected client: AptosClient;
    protected account?: AptosAccount;
    protected moduleAddress: string;

    constructor(nodeUrl: string = CONFIG.NODE_URL, moduleAddress: string = CONFIG.MODULE_ADDRESS) {
        this.client = new AptosClient(nodeUrl);
        this.moduleAddress = moduleAddress;
    }

    setAccount(account: AptosAccount) {
        this.account = account;
    }

    protected async executeTransaction(payload: Types.EntryFunctionPayload): Promise<string> {
        if (!this.account) throw new Error("Account not set");

        try {
            const txn = await this.client.generateTransaction(this.account.address(), payload);
            const signedTxn = await this.client.signTransaction(this.account, txn);
            const result = await this.client.submitTransaction(signedTxn);
            await this.client.waitForTransaction(result.hash);
            return result.hash;
        } catch (error) {
            console.error("Transaction error:", error);
            throw error;
        }
    }

    protected async viewFunction(func: string, args: any[] = []): Promise<any> {
        try {
            const payload: Types.ViewRequest = {
                function: `${this.moduleAddress}::${func}`,
                type_arguments: [],
                arguments: args
            };
            return await this.client.view(payload);
        } catch (error) {
            console.error(`View function error (${func}):`, error);
            throw error;
        }
    }
}

// Account Manager
class AccountManager extends BaseManager {
    private faucetClient: FaucetClient;

    constructor(
        nodeUrl: string = CONFIG.NODE_URL,
        faucetUrl: string = CONFIG.FAUCET_URL,
        moduleAddress: string = CONFIG.MODULE_ADDRESS
    ) {
        super(nodeUrl, moduleAddress);
        this.faucetClient = new FaucetClient(nodeUrl, faucetUrl);
    }

    createAccount(privateKeyHex?: string): AptosAccount {
        this.account = privateKeyHex
            ? new AptosAccount(HexString.ensure(privateKeyHex).toUint8Array())
            : new AptosAccount();
        return this.account;
    }

    async getBalance(): Promise<AccountBalance> {
        if (!this.account) throw new Error("Account not set");

        const resources = await this.client.getAccountResources(this.account.address());
        const aptosCoin = resources.find((r) => r.type === "0x1::coin::CoinStore<0x1::aptos_coin::AptosCoin>");
        
        if (!aptosCoin?.data || !('coin' in aptosCoin.data)) {
            throw new Error("Could not retrieve balance");
        }

        const amount = Number((aptosCoin.data as any).coin.value);
        return {
            amount,
            decimals: 8,
            formatted: AptosUtils.formatBalance(amount)
        };
    }

    async fundAccount(amount: number = 100_000_000): Promise<void> {
        if (!this.account) throw new Error("Account not set");
        await this.faucetClient.fundAccount(this.account.address(), amount);
        await this.getBalance();
    }
}

// Campaign Manager
class CampaignManager extends BaseManager {
    async createCampaign(
        title: string,
        description: string,
        prompt: string,
        unitPrice: number,
        minimumContribution: number,
        rewardPool: number
    ): Promise<string> {
        const payload = AptosUtils.createEntryPayload(
            `${this.moduleAddress}::CampaignManager::create_campaign`,
            [
                AptosUtils.stringToBytes(title),
                AptosUtils.stringToBytes(description),
                AptosUtils.stringToBytes(prompt),
                unitPrice.toString(),
                minimumContribution.toString(),
                rewardPool.toString()
            ]
        );

        return this.executeTransaction(payload);
    }

    async getCampaign(campaignId: number): Promise<Campaign | null> {
        try {
            const response = await this.viewFunction("CampaignManager::get_campaign", [campaignId.toString()]);
            return this.parseCampaignResponse(response[0]);
        } catch {
            return null;
        }
    }

    async getAllCampaigns(): Promise<Campaign[]> {
        try {
            const response = await this.viewFunction("CampaignManager::get_all_campaigns");
            return (response[0] as any[]).map(camp => this.parseCampaignResponse(camp));
        } catch {
            return [];
        }
    }

    private parseCampaignResponse(response: any): Campaign {
        return {
            id: Number(response.id),
            creator: response.creator,
            title: AptosUtils.bytesToString(response.title),
            description: AptosUtils.bytesToString(response.description),
            prompt: AptosUtils.bytesToString(response.prompt),
            reward_pool: Number(response.reward_pool),
            remaining_reward: Number(response.remaining_reward),
            unit_price: Number(response.unit_price),
            minimum_contribution: Number(response.minimum_contribution),
            active: response.active
        };
    }
}

// Contribution Manager
class ContributionManager extends BaseManager {
    async addTrustedKey(publicKey: string): Promise<string> {
        const payload = AptosUtils.createEntryPayload(
            `${this.moduleAddress}::ContributionManager::add_trusted_key`,
            [AptosUtils.hexToBytes(publicKey)]
        );

        return this.executeTransaction(payload);
    }

    async addContribution(
        campaignId: number,
        dataCount: number,
        storeCid: string,
        score: number,
        signature: string
    ): Promise<string> {
        const payload = AptosUtils.createEntryPayload(
            `${this.moduleAddress}::ContributionManager::add_contribution`,
            [
                campaignId.toString(),
                dataCount.toString(),
                AptosUtils.stringToBytes(storeCid),
                score.toString(),
                AptosUtils.hexToBytes(signature)
            ]
        );

        return this.executeTransaction(payload);
    }

    async getCampaignContributions(campaignId: number): Promise<Contribution[]> {
        try {
            const response = await this.viewFunction(
                "ContributionManager::get_campaign_contributions",
                [campaignId.toString()]
            );
            return (response[0] as any[]).map(contrib => this.parseContributionResponse(contrib));
        } catch {
            return [];
        }
    }

    async getContributorContributions(contributor: string): Promise<Contribution[]> {
        try {
            const response = await this.viewFunction(
                "ContributionManager::get_contributor_contributions",
                [contributor]
            );
            return (response[0] as any[]).map(contrib => this.parseContributionResponse(contrib));
        } catch {
            return [];
        }
    }

    private parseContributionResponse(response: any): Contribution {
        return {
            campaign_id: Number(response.campaign_id),
            contributor: response.contributor,
            data_count: Number(response.data_count),
            store_cid: AptosUtils.bytesToString(response.store_cid),
            score: Number(response.score),
            signature: Buffer.from(response.signature).toString('hex')
        };
    }
}

// Main SDK Class
export class AptosMoveSDK {
    readonly account: AccountManager;
    readonly campaign: CampaignManager;
    readonly contribution: ContributionManager;

    constructor(
        nodeUrl: string = CONFIG.NODE_URL,
        faucetUrl: string = CONFIG.FAUCET_URL,
        moduleAddress: string = CONFIG.MODULE_ADDRESS
    ) {
        this.account = new AccountManager(nodeUrl, faucetUrl, moduleAddress);
        this.campaign = new CampaignManager(nodeUrl, moduleAddress);
        this.contribution = new ContributionManager(nodeUrl, moduleAddress);
    }

    setAccount(privateKeyHex?: string): AptosAccount {
        const account = this.account.createAccount(privateKeyHex);
        this.campaign.setAccount(account);
        this.contribution.setAccount(account);
        return account;
    }
}

// CLI Komutları
async function handleCliCommands() {
    const args = process.argv.slice(2);
    const command = args[0];

    // Default değerler
    const DEFAULT_VALUES = {
        campaign: {
            title: "Test Campaign",
            description: "Test Campaign Description",
            prompt: "Test Campaign Prompt",
            unitPrice: 0.01,      // 0.01 APT
            minContribution: 0,    // 0 APT
            rewardPool: 0.5       // 0.5 APT
        },
        contribution: {
            dataCount: 1,
            storeCid: "QmTest",
            score: 95
        }
    };

    // İmza oluşturucu
    const dataSigner = new DataSigner();

    try {
        const sdk = new AptosMoveSDK();
        
        // Özel anahtarı env'den al ve hesabı oluştur
        const privateKey = process.env.TRUSTED_PRIVATE_KEY;
        if (!privateKey) {
            throw new Error("TRUSTED_PRIVATE_KEY env değişkeni bulunamadı!");
        }
        
        const account = sdk.setAccount(privateKey);
        console.log("\nHesap yüklendi!");
        console.log("Adres:", account.address().hex());
        
        const balance = await sdk.account.getBalance();
        console.log("Bakiye:", balance.formatted, "APT\n");

        switch (command) {
            case "--add-trusted-key": {
                if (args.length < 2) {
                    console.error("Kullanım: npm start -- --add-trusted-key <publicKey>");
                    process.exit(1);
                }

                const publicKey = args[1];
                console.log("\nGüvenilir anahtar ekleniyor...");
                console.log("Public Key:", publicKey);

                const txn = await sdk.contribution.addTrustedKey(publicKey);
                console.log("\nGüvenilir anahtar başarıyla eklendi!");
                console.log("Transaction Hash:", txn);
                break;
            }

            case "--create-campaign": {
                const { title, description, prompt, unitPrice, minContribution, rewardPool } = DEFAULT_VALUES.campaign;
                
                // APT miktarlarını octa'ya çevirme (1 APT = 100_000_000 octa)
                const unitPriceOcta = Math.floor(unitPrice * 100_000_000);
                const rewardPoolOcta = Math.floor(rewardPool * 100_000_000);
                const minContribOcta = Math.floor(minContribution * 100_000_000);

                console.log("\nKampanya oluşturuluyor...");
                console.log("Title:", title);
                console.log("Description:", description);
                console.log("Prompt:", prompt);
                console.log("Unit Price:", unitPrice, "APT");
                console.log("Minimum Contribution:", minContribution, "APT");
                console.log("Reward Pool:", rewardPool, "APT");

                const txn = await sdk.campaign.createCampaign(
                    title,
                    description,
                    prompt,
                    unitPriceOcta,
                    minContribOcta,
                    rewardPoolOcta
                );
                console.log("\nKampanya başarıyla oluşturuldu!");
                console.log("Transaction Hash:", txn);
                break;
            }

            case "--list-campaigns": {
                console.log("\nKampanyalar listeleniyor...");
                const campaigns = await sdk.campaign.getAllCampaigns();
                
                if (campaigns.length === 0) {
                    console.log("Henüz hiç kampanya oluşturulmamış.");
                    break;
                }

                campaigns.forEach((campaign, index) => {
                    console.log(`\nKampanya #${index + 1}:`);
                    console.log("ID:", campaign.id);
                    console.log("Creator:", campaign.creator);
                    console.log("Title:", campaign.title);
                    console.log("Description:", campaign.description);
                    console.log("Prompt:", campaign.prompt);
                    console.log("Reward Pool:", campaign.reward_pool / 100_000_000, "APT");
                    console.log("Remaining Reward:", campaign.remaining_reward / 100_000_000, "APT");
                    console.log("Unit Price:", campaign.unit_price / 100_000_000, "APT");
                    console.log("Minimum Contribution:", campaign.minimum_contribution / 100_000_000, "APT");
                    console.log("Active:", campaign.active);
                    console.log("----------------------------------------");
                });
                break;
            }

            case "--add-contribution": {
                if (args.length < 2) {
                    console.error("Kullanım: npm start -- --add-contribution <campaignId>");
                    process.exit(1);
                }

                const campaignId = parseInt(args[1]);
                const { dataCount, storeCid, score } = DEFAULT_VALUES.contribution;

                // Katkı verilerini imzala
                const signature = dataSigner.signContributionData(
                    campaignId,
                    dataCount,
                    storeCid,
                    score
                );

                console.log("\nKatkı ekleniyor...");
                console.log("Campaign ID:", campaignId);
                console.log("Data Count:", dataCount);
                console.log("Store CID:", storeCid);
                console.log("Score:", score);
                console.log("Signature:", signature);

                const txn = await sdk.contribution.addContribution(
                    campaignId,
                    dataCount,
                    storeCid,
                    score,
                    signature
                );
                console.log("\nKatkı başarıyla eklendi!");
                console.log("Transaction Hash:", txn);
                break;
            }

            case "--list-contributions": {
                if (args.length < 2) {
                    console.error("Kullanım: npm start -- --list-contributions <campaignId>");
                    process.exit(1);
                }

                const campaignId = parseInt(args[1]);
                console.log(`\nKampanya #${campaignId} katkıları listeleniyor...`);
                
                const contributions = await sdk.contribution.getCampaignContributions(campaignId);
                
                if (contributions.length === 0) {
                    console.log("Bu kampanyaya henüz katkı yapılmamış.");
                    break;
                }

                contributions.forEach((contribution, index) => {
                    console.log(`\nKatkı #${index + 1}:`);
                    console.log("Campaign ID:", contribution.campaign_id);
                    console.log("Contributor:", contribution.contributor);
                    console.log("Data Count:", contribution.data_count);
                    console.log("Store CID:", contribution.store_cid);
                    console.log("Score:", contribution.score);
                    console.log("----------------------------------------");
                });
                break;
            }

            case "--help": {
                console.log("\nKullanılabilir komutlar:");
                console.log("1. Güvenilir anahtar ekleme:");
                console.log("   npm start -- --add-trusted-key <publicKey>");
                
                console.log("\n2. Kampanya oluşturma (default değerlerle):");
                console.log("   npm start -- --create-campaign");
                
                console.log("\n3. Kampanyaları listeleme:");
                console.log("   npm start -- --list-campaigns");
                
                console.log("\n4. Katkı ekleme:");
                console.log("   npm start -- --add-contribution <campaignId>");
                
                console.log("\n5. Katkıları listeleme:");
                console.log("   npm start -- --list-contributions <campaignId>");
                break;
            }

            default: {
                console.log("Bilinmeyen komut. Yardım için: npm start -- --help");
                break;
            }
        }
    } catch (error) {
        console.error("Hata:", error);
    }
}

// Ana fonksiyonu CLI handler ile değiştir
if (require.main === module) {
    handleCliCommands();
}

export default AptosMoveSDK;
