import { AptosClient, AptosAccount, FaucetClient, Types, HexString } from "aptos";

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
    private faucetClient: FaucetClient;
    private account: AptosAccount;
    private moduleAddress: string;

    constructor(privateKeyHex: string) {
        this.client = new AptosClient(NODE_URL);
        this.faucetClient = new FaucetClient(NODE_URL, FAUCET_URL);
        this.account = new AptosAccount(
            HexString.ensure(privateKeyHex).toUint8Array()
        );
        this.moduleAddress = "0xc1b4e3ba40bb75b294bb12ade0439be98611c0ed79ed899f91191e726ebab79e";
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
        dataSpec: string,
        qualityCriteria: string,
        rewardPool: number
    ): Promise<void> {
        try {
            const createTxn = await this.client.generateTransaction(this.account.address(), {
                function: `${this.moduleAddress}::CampaignManager::create_campaign`,
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
            data_spec: Buffer.from(response.data_spec.slice(2), 'hex').toString(),
            quality_criteria: Buffer.from(response.quality_criteria.slice(2), 'hex').toString(),
            reward_pool: Number(response.reward_pool),
            active: response.active
        };
    }

    async lockFunds(campaignId: number, amount: number): Promise<void> {
        try {
            const lockTxn = await this.client.generateTransaction(this.account.address(), {
                function: `${this.moduleAddress}::EscrowManager::lock_funds`,
                type_arguments: [],
                arguments: [
                    campaignId.toString(),
                    amount.toString(),
                    this.moduleAddress
                ]
            });

            const signedLockTxn = await this.client.signTransaction(this.account, lockTxn);
            const lockResult = await this.client.submitTransaction(signedLockTxn);
            await this.client.waitForTransaction(lockResult.hash);
            console.log("Funds locked successfully!");
        } catch (e) {
            console.log("Fund locking error:", e);
            throw e;
        }
    }

    async getLockedAmount(campaignId: number): Promise<number> {
        try {
            const payload: Types.ViewRequest = {
                function: `${this.moduleAddress}::EscrowManager::get_locked_amount`,
                type_arguments: [],
                arguments: [campaignId.toString(), this.moduleAddress]
            };

            const response = await this.client.view(payload);
            return Number(response[0]);
        } catch (e) {
            console.log("Error getting locked amount:", e);
            return 0;
        }
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
    console.log("\nCreating new campaign...");
    await campaignManager.createCampaign(
        "Test Campaign 1",
        "Quality Criteria 1",
        50_000_000 // 0.5 APT
    );

    // List all campaigns
    console.log("\nListing campaigns...");
    const campaigns = await campaignManager.listAllCampaigns();
    console.log("\nTotal number of campaigns:", campaigns.length);
    for (const campaign of campaigns) {
        console.log("\nCampaign Details:");
        console.log("ID:", campaign.id);
        console.log("Creator:", campaign.creator);
        console.log("Data Specification:", campaign.data_spec);
        console.log("Quality Criteria:", campaign.quality_criteria);
        console.log("Reward Pool:", campaign.reward_pool / 100_000_000, "APT");
        console.log("Active:", campaign.active);

        console.log("Checking locked amount for campaign from escrow manager", campaign.id);
        const lockedAmount = await campaignManager.getLockedAmount(campaign.id);
        console.log("Locked amount for campaign", campaign.id, ":", lockedAmount / 100_000_000, "APT");
        console.log("\n----------------------------------------");
    }

}

main().catch(console.error);
