import CampaignManager from "../classes/CampaignManager";

export default async function addContribution(
  campaignManager: CampaignManager,
  contribution: {
    campaignID: number;
    data_count: number;
    data: string;
    verified: boolean;
  }
) {
  console.log("\nAdding a test contribution...");
  const tx = await campaignManager.addContribution(
    contribution.campaignID,
    contribution.data_count,
    contribution.data,
    contribution.verified
  );

  return tx;
}
