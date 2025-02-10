import { AptosAccount } from "aptos";

import { CampaignManager } from "./classes/CampaignManager";

import listAllCampaigns from "./functions/list_all_campaigns";
import addContribution from "./functions/add_contribution";
import listContributions from "./functions/list_contributions";
import createNewCampaign from "./functions/create_new_campaign";

import { NewContribution, NewCampaign } from "./types";

async function main() {
  // Create a new test account
  const account = new AptosAccount();
  console.log("New account created");
  console.log("Private Key:", account.toPrivateKeyObject().privateKeyHex);
  console.log("Address:", account.address().hex());

  const campaignManager = new CampaignManager(
    account.toPrivateKeyObject().privateKeyHex
  );

  // Add APT to account
  console.log("\nAdding APT to account...");
  await campaignManager.fundAccount();

  // Create new campaign

  const campaign: NewCampaign = {
    title: "Test Campaign",
    description: "Test Campaign Description",
    data_spec: "Test Campaign Data Specification",
    reward_pool: 10_000_000,
    unit_price: 100_000,
  };

  //console.log(await createNewCampaign(campaignManager, campaign));

  // List all campaigns
  const campaigns = await listAllCampaigns(campaignManager);

  // Test contribution adding

  const contribution: NewContribution = {
    campaignID: campaigns[0].id,
    data_count: 1,
    data: "Test contribution data",
    verified: true,
  };
  const tx = await addContribution(campaignManager, contribution);
  console.log("Transaction hash:", tx);
  // Get and display contributions
  await listContributions(campaignManager, campaigns);
}

main().catch(console.error);
