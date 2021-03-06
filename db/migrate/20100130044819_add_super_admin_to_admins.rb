class AddSuperAdminToAdmins < ActiveRecord::Migration
  def self.up
    change_table :admins do |t|
      t.boolean :super_admin, :default => false
    end
    Admin.reset_column_information
    Site.each do
      Setting.get(:access, :super_admins).each do |email|
        Person.find_all_by_email(email).each do |person|
          admin = Admin.create!(:super_admin => true)
          person.admin = admin
          person.save!
        end
      end
    end
    Setting.delete_all("section = 'Access' and name = 'Super Admins'")
  end

  def self.down
    Site.each do |site|
      site.settings.create!(
        :section => 'Access',
        :name    => 'Super Admins',
        :format  => 'list',
        :value   => Admin.find_all_by_super_admin(true).map { |a| a.person.email }
      )
    end
    change_table :admins do |t|
      t.remove :super_admin
    end
  end
end
