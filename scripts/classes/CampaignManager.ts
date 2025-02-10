import {
  AptosClient,
  AptosAccount,
  FaucetClient,
  Types,
  HexString,
} from "aptos";

import dotenv from "dotenv";

dotenv.config();

const NODE_URL = process.env.NODE_URL || "http://127.0.0.1:8080/v1";
const FAUCET_URL = process.env.FAUCET_URL || "http://127.0.0.1:8081";

import { Campaign, Contribution, NewCampaign } from "../types";

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
    this.moduleAddress = process.env.CAMPAIGN_MANAGER_ADDRESS || "";
  }

  getAddress(): string {
    return this.account.address().hex();
  }

  async fundAccount(): Promise<void> {
    try {
      await this.faucetClient.fundAccount(this.account.address(), 100_000_000);

      // Check account balance
      const resources = await this.client.getAccountResources(
        this.account.address()
      );
      const aptosCoin = resources.find(
        (r) => r.type === "0x1::coin::CoinStore<0x1::aptos_coin::AptosCoin>"
      );

      if (
        aptosCoin?.data &&
        typeof aptosCoin.data === "object" &&
        "coin" in aptosCoin.data
      ) {
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

  async createCampaign(campaign: NewCampaign): Promise<void> {
    try {
      const createTxn = await this.client.generateTransaction(
        this.account.address(),
        {
          function: `${this.moduleAddress}::CampaignManager::create_campaign`,
          type_arguments: [],
          arguments: [
            campaign.title,
            campaign.description,
            campaign.data_spec,
            campaign.unit_price,
            campaign.reward_pool,
          ],
        }
      );

      const signedCreateTxn = await this.client.signTransaction(
        this.account,
        createTxn
      );
      const createResult = await this.client.submitTransaction(signedCreateTxn);
      await this.client.waitForTransaction(createResult.hash);
      console.log(
        "New campaign created successfully! Hash: ",
        createResult.hash
      );
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
        arguments: [campaignId.toString()],
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
        arguments: [],
      };

      const response = await this.client.view(payload);
      const campaigns = response[0] as any[];
      return campaigns.map((camp) => this.parseCampaignResponse(camp));
    } catch (e) {
      console.log("Error listing campaigns:", e);
      return [];
    }
  }

  private parseCampaignResponse(response: any): Campaign {
    return {
      id: Number(response.id),
      creator: response.creator,
      title: response.title,
      description: response.description,
      data_spec: response.data_spec,
      reward_pool: Number(response.reward_pool),
      remaining_reward: Number(response.remaining_reward),
      unit_price: Number(response.unit_price),
      active: response.active,
    };
  }

  async addContribution(
    campaignId: number,
    dataCount: number,
    data: string,
    verified: boolean = false
  ): Promise<string> {
    try {
      const addContribTxn = await this.client.generateTransaction(
        this.account.address(),
        {
          function: `${this.moduleAddress}::ContributionManager::add_contribution`,
          type_arguments: [],
          arguments: [campaignId, dataCount, data, verified],
        }
      );

      const signedTxn = await this.client.signTransaction(
        this.account,
        addContribTxn
      );
      const result = await this.client.submitTransaction(signedTxn);
      await this.client.waitForTransaction(result.hash);
      console.log("Contribution added successfully!");

      return result.hash;
    } catch (e) {
      console.log("Contribution addition error:", e);
      throw e;
    }
  }

  async getCampaignContributions(campaignId: number): Promise<Contribution[]> {
    try {
      if (campaignId === undefined) {
        throw new Error("Campaign ID is undefined");
      }
      const payload: Types.ViewRequest = {
        function: `${this.moduleAddress}::ContributionManager::get_campaign_contributions`,
        type_arguments: [],
        arguments: [campaignId.toString()],
      };

      const response = await this.client.view(payload);
      const contributions = response[0] as any[];
      return contributions.map((contrib) =>
        this.parseContributionResponse(contrib)
      );
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
      data: Buffer.from(response.data.slice(2), "hex").toString(),
      verified: response.verified,
    };
  }
}

export default CampaignManager;
export { CampaignManager };
