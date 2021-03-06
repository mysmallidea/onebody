class UpdateLeaderOnGroups < ActiveRecord::Migration
  def self.up
    Site.each do
      Group.find_all_by_leader_id(nil).each do |group|
        group.leader = group.admins.first
        group.save(false)
      end
    end
  end

  def self.down
    # none
  end
end
