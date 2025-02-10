import { AptosClient, AptosAccount, FaucetClient, Types, HexString } from "aptos";

const NODE_URL = "https://fullnode.devnet.aptoslabs.com";
const FAUCET_URL = "https://faucet.devnet.aptoslabs.com";

interface Campaign {
    id: number;
    creator: string;
    title: string;
    description: string;
    data_spec: string;
    reward_pool: number;
    remaining_reward: number;
    unit_price: number;
    active: boolean;
}

interface Contribution {
    campaign_id: number;
    contributor: string;
    data_count: number;
    data: string;
    verified: boolean;
}

class CampaignManager {
    private client: AptosClient;
    private faucetClient: FaucetClient;
    private account: AptosAccount;
    private moduleAddress: string;

    constructor(privateKeyHex: string) {
        this.client = new AptosClient(NODE_URL);
        this.faucetClient = new FaucetClient(NODE_URL, FAUCET_URL);
        this.account = new AptosAccount(
            HexString.ensure(privateKeyHex).toUint8Array()
        );
        this.moduleAddress = "0xea810f84d376c13e44a663cf271c45731076218407ae1760a4ac85b3d955a0f6";
    }

    getAddress(): string {
        return this.account.address().hex();
    }

    async fundAccount(): Promise<void> {
        try {
            await this.faucetClient.fundAccount(this.account.address(), 100_000_000);
            
            // Check account balance
            const resources = await this.client.getAccountResources(this.account.address());
            const aptosCoin = resources.find((r) => r.type === "0x1::coin::CoinStore<0x1::aptos_coin::AptosCoin>");
            
            if (aptosCoin?.data && typeof aptosCoin.data === 'object' && 'coin' in aptosCoin.data) {
                const balance = (aptosCoin.data as any).coin.value;
                console.log("Current balance:", Number(balance) / 100_000_000, "APT");
            } else {
                console.log("Could not retrieve balance");
            }
        } catch (e) {
            console.log("Faucet error:", e);
            throw e;
        }
    }

    async createCampaign(
        title: string,
        description: string,
        dataSpec: string,
        unitPrice: number,
        rewardPool: number
    ): Promise<void> {
        try {
            const createTxn = await this.client.generateTransaction(this.account.address(), {
                function: `${this.moduleAddress}::CampaignManager::create_campaign`,
                type_arguments: [],
                arguments: [
                    Array.from(Buffer.from(title)),
                    Array.from(Buffer.from(description)),
                    Array.from(Buffer.from(dataSpec)),
                    unitPrice.toString(),
                    rewardPool.toString()
                ]
            });

            const signedCreateTxn = await this.client.signTransaction(this.account, createTxn);
            const createResult = await this.client.submitTransaction(signedCreateTxn);
            await this.client.waitForTransaction(createResult.hash);
            console.log("New campaign created successfully!");
        } catch (e) {
            console.log("Campaign creation error:", e);
            throw e;
        }
    }

    async getCampaign(campaignId: number): Promise<Campaign | null> {
        try {
            const payload: Types.ViewRequest = {
                function: `${this.moduleAddress}::CampaignManager::get_campaign`,
                type_arguments: [],
                arguments: [campaignId.toString()]
            };

            const response = await this.client.view(payload);
            return this.parseCampaignResponse(response[0]);
        } catch (e) {
            console.log("Could not retrieve campaign:", e);
            return null;
        }
    }

    async listAllCampaigns(): Promise<Campaign[]> {
        try {
            const payload: Types.ViewRequest = {
                function: `${this.moduleAddress}::CampaignManager::get_all_campaigns`,
                type_arguments: [],
                arguments: []
            };

            const response = await this.client.view(payload);
            const campaigns = response[0] as any[];
            return campaigns.map(camp => this.parseCampaignResponse(camp));
        } catch (e) {
            console.log("Error listing campaigns:", e);
            return [];
        }
    }

    private parseCampaignResponse(response: any): Campaign {
        return {
            id: Number(response.id),
            creator: response.creator,
            title: Buffer.from(response.title.slice(2), 'hex').toString(),
            description: Buffer.from(response.description.slice(2), 'hex').toString(),
            data_spec: Buffer.from(response.data_spec.slice(2), 'hex').toString(),
            reward_pool: Number(response.reward_pool),
            remaining_reward: Number(response.remaining_reward),
            unit_price: Number(response.unit_price),
            active: response.active
        };
    }

    async addContribution(
        campaignId: number,
        dataCount: number,
        data: string,
        verified: boolean = false
    ): Promise<void> {
        try {
            const addContribTxn = await this.client.generateTransaction(this.account.address(), {
                function: `${this.moduleAddress}::ContributionManager::add_contribution`,
                type_arguments: [],
                arguments: [
                    campaignId.toString(),
                    dataCount.toString(),
                    Array.from(Buffer.from(data)),
                    verified
                ]
            });

            const signedTxn = await this.client.signTransaction(this.account, addContribTxn);
            const result = await this.client.submitTransaction(signedTxn);
            await this.client.waitForTransaction(result.hash);
            console.log("Contribution added successfully!");
        } catch (e) {
            console.log("Contribution addition error:", e);
            throw e;
        }
    }

    async getCampaignContributions(campaignId: number): Promise<Contribution[]> {
        try {
            const payload: Types.ViewRequest = {
                function: `${this.moduleAddress}::ContributionManager::get_campaign_contributions`,
                type_arguments: [],
                arguments: [campaignId.toString()]
            };

            const response = await this.client.view(payload);
            const contributions = response[0] as any[];
            return contributions.map(contrib => this.parseContributionResponse(contrib));
        } catch (e) {
            console.log("Error getting campaign contributions:", e);
            return [];
        }
    }

    private parseContributionResponse(response: any): Contribution {
        return {
            campaign_id: Number(response.campaign_id),
            contributor: response.contributor,
            data_count: Number(response.data_count),
            data: Buffer.from(response.data.slice(2), 'hex').toString(),
            verified: response.verified
        };
    }
}

async function main() {
    // Create a new test account
    const account = new AptosAccount();
    console.log("New account created");
    console.log("Private Key:", account.toPrivateKeyObject().privateKeyHex);
    console.log("Address:", account.address().hex());

    const campaignManager = new CampaignManager(account.toPrivateKeyObject().privateKeyHex);

    // Add APT to account
    console.log("\nAdding APT to account...");
    await campaignManager.fundAccount();


    

    // Create new campaign
    /*
    console.log("\nCreating new campaign...");
    await campaignManager.createCampaign(
        "Test Campaign 4",
        "Test Campaign 4 Description",
        "Test Campaign 4 Data Specification",
        1_000_000,   // 0.01 APT unit price
        50_000_000  // 0.5 APT reward pool
    );
    */
    
    // List all campaigns
    console.log("\nListing campaigns...");
    const campaigns = await campaignManager.listAllCampaigns();
    console.log("\nTotal number of campaigns:", campaigns.length);
    for (const campaign of campaigns) {
        console.log("\nCampaign Details:");
        console.log("ID:", campaign.id);
        console.log("Creator:", campaign.creator);
        console.log("Title:", campaign.title);
        console.log("Description:", campaign.description);
        console.log("Data Specification:", campaign.data_spec);
        console.log("Reward Pool:", campaign.reward_pool / 100_000_000, "APT");
        console.log("Remaining Reward:", campaign.remaining_reward / 100_000_000, "APT");
        console.log("Unit Price:", campaign.unit_price / 100_000_000, "APT");
        console.log("Active:", campaign.active);
        console.log("\n----------------------------------------");
    }

    
    // Test contribution adding

    
    console.log("\nAdding a test contribution...");
    await campaignManager.addContribution(
        campaigns[1].id,  
        2,              // data_count
        "Test contribution data",
        true            // verified
    );
    

    // Get and display contributions
    console.log("\nListing contributions for campaign...");
    const contributions = await campaignManager.getCampaignContributions(campaigns[1].id);
    for (const contribution of contributions) {
        console.log("\nContribution Details:");
        console.log("Campaign ID:", contribution.campaign_id);
        console.log("Contributor:", contribution.contributor);
        console.log("Data Count:", contribution.data_count);
        console.log("Data:", contribution.data);
        console.log("Verified:", contribution.verified);
        console.log("\n----------------------------------------");
    }
}

main().catch(console.error);
