# Read about factories at https://github.com/thoughtbot/factory_girl
# == Schema Information
#
# Table name: users
#
#  id                    :integer          not null, primary key
#  login                 :string(255)
#  email                 :string(255)
#  crypted_password      :string(40)
#  salt                  :string(40)
#  created_at            :datetime
#  updated_at            :datetime
#  remember_token        :string(255)
#  remember_created_at   :datetime
#  status                :integer          default(0)
#  last_login            :datetime
#  activation_code       :string(40)
#  activated_at          :datetime
#  password_reset_code   :string(40)
#  user_role_id          :integer          default(0)
#  representative_id     :integer
#  previous_login_date   :datetime
#  identity_url          :string(255)
#  accepted_tos_at       :datetime
#  authentication_token  :string(255)
#  facebook_uid          :string(255)
#  possible_states       :text
#  possible_districts    :text
#  state                 :string(2)
#  district              :integer
#  district_needs_update :boolean          default(FALSE)
#  password_digest       :string(255)
#

FactoryGirl.define do
  factory :jdoe, class: User do
    id 1
    email "jdoe@example.com"
    login "jdoe"
    state "AL"
    district 1
    activated_at Time.now
    accepted_tos_at Time.new(2014, 01, 01)
    password "password"
  end

  factory :user do
    login { "#{Faker::Name.first_name}123".gsub(/[^a-zA-Z]/,'') }
    email { "#{login.gsub(/[^a-zA-Z]/,'')}@example.com" }
    state "AL"
    district 1
    accepted_tos_at Time.new(2014, 01, 01)
    password "password"
    status 1
    district_needs_update false
    association :user_profile, :strategy => :build
    user_notification_options
  end

  factory :user_1, class: User do
    activated_at Time.new(2008, 01, 14)
    created_at Time.new(2008, 01, 13)
    last_login Time.new(2010, 04, 02)
    updated_at Time.new(2010, 04, 02)
    previous_login_date Time.new(2010, 03, 26, 14, 41, 25.196049)
    id 12
    representative_id 400301
    user_role_id 2
    accepted_tos_at Time.new(2009, 03, 24, 23, 42, 42.592366)
    state 'MA'
    login 'donnyshaw'
    district 1
    email 'donnydonnyzxcasdqwe@gmail.com'
    password "password"
  end

  factory :user_2, class: User do
    activated_at Time.new(2010, 01, 13, 16, 50, 45.022104)
    created_at Time.new(2010, 01, 13, 10, 48, 47.772348)
    last_login Time.new(2010, 04, 06, 14, 26, 56.149317)
    updated_at Time.new(2010, 04, 06, 14, 26, 56.151032)
    previous_login_date Time.new(2010, 04, 05, 11, 34, 47.54711)
    id 100442
    representative_id 400295
    user_role_id 2
    accepted_tos_at Time.new(2010, 01, 13, 10, 48, 47.532932)
    state 'DC'
    status 1
    login 'enaing'
    district 0
    email 'enaing@gmail.com'
    password "password"
  end

  factory :user_3, class: User do
    status 1
    login 'JoeCool'
    email 'joe_cool@example.com'
    crypted_password 'abcdefg'
    state 'VA'
    district 8
    accepted_tos_at 10.minutes.ago
    activated_at 10.minutes.ago
    password "password"
  end
end
