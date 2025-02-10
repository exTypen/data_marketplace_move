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

interface NewCampaign {
  title: string;
  description: string;
  data_spec: string;
  unit_price: number;
  reward_pool: number;
}

interface Contribution {
  campaign_id: number;
  contributor: string;
  data_count: number;
  data: string;
  verified: boolean;
}

interface NewContribution {
  campaignID: number;
  data_count: number;
  data: string;
  verified: boolean;
}

export { Campaign, Contribution, NewCampaign, NewContribution };
