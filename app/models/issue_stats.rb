# == Schema Information
#
# Table name: issue_stats
#
#  subject_id         :integer          not null, primary key
#  entered_top_viewed :datetime
#

class IssueStats < ActiveRecord::Base
  set_primary_key :subject_id
  
  belongs_to :subject
end
