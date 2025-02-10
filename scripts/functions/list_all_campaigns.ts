import CampaignManager from "../classes/CampaignManager";

export default async function listAllCampaigns(
  campaignManager: CampaignManager
) {
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
    console.log(
      "Remaining Reward:",
      campaign.remaining_reward / 100_000_000,
      "APT"
    );
    console.log("Unit Price:", campaign.unit_price / 100_000_000, "APT");
    console.log("Active:", campaign.active);
    console.log("\n----------------------------------------");
  }

  return campaigns;
}
