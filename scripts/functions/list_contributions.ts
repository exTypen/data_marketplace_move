import CampaignManager from "../classes/CampaignManager";
import { Campaign } from "../types";

export default async function listContributions(
  campaignManager: CampaignManager,
  campaigns: Campaign[]
) {
  console.log("\nListing contributions for campaign...");
  const contributions = await campaignManager.getCampaignContributions(
    campaigns[0].id
  );
  console.log(contributions);
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
