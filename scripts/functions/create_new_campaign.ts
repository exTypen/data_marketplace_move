import { CampaignManager } from "../classes/CampaignManager";
import { NewCampaign } from "../types";

export default async function createNewCampaign(
  campaignManager: CampaignManager,
  campaign: NewCampaign
) {
  console.log("\nCreating new campaign...");
  await campaignManager.createCampaign(campaign);
  console.log("Campaign created successfully");
  return campaign;
}
