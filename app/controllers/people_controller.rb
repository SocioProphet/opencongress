require_dependency 'person'
require_dependency 'email_congress'

class PeopleController < ApplicationController
  include ActionView::Helpers::NumberHelper

  verify :method => :post, :only => [:most_viewed_text_update]
  before_filter :page_view, :only => :show
  #before_filter :person_profile_shared, :only => [:show, :comments, :bills, :voting_history, :money, :news_blogs, :videos, :news, :blogs]
  before_filter :person_profile_shared, :only => [:show, :comments, :bills, :voting_history, :money, :videos]
  skip_before_filter :protect_from_forgery, :only => :zipcodelookup

  def index
    @page_title = "Senators and Representatives"

  end

  ##
  # Sends an email to the specified person if said person has
  # a known email address. As of commit c09f9c9e on 2013-08-28
  # no such email addresses are avialable. Leaving this code in
  # place for future use, via formageddon-provided email addresses.
  def send_person
    params.delete(:commit)
    person = Person.find(params[:id])
    email = person.email
    if email
      Emailer::send_person(email, 'visitor@opencongress.org',
        params[:subject], params[:msg]).deliver if email
      action_done = "Email sent"
    else
      action_done = "Sorry but #{person.name} does not have an email address."
    end

    flash[:notice] = action_done
    respond_to do |wants|
      wants.html do
        # Handle users with javascript disabled
        redirect_to :action => :show, :id => person.id
      end
      wants.js {}
    end
  end

  def people_list
    congress = params[:congress] ? params[:congress].to_i : Settings.default_congress
    person_type = (params[:person_type] == 'senators') ? 'sen' : 'rep'
    @person_type = (person_type == 'sen') ? :senators : :representatives
    @sort = (params[:sort] || :state).to_sym

    @sort_by = case @sort
      when :name
        'lastname asc'
      when :popular
        'view_count desc'
      when :approval
        'person_approval_average desc'
      else
        'state, lastname'
      end

    if @sort == :popular || @sort == :approval
      @days = days_from_params(params[:days])
    end

    people_cache_key = "Person.list_chamber(#{@person_type.to_s}, #{congress.to_s}, #{@sort_by.to_s})"
    @people = Rails.cache.fetch(people_cache_key) do
      Person.list_chamber(person_type, congress, @sort_by)
    end

    if @sort == :popular
      @atom = {'link' => url_for(:only_path => false, :controller => 'people', :action => 'atom_top20', :type => person_type), 'title' => "Top 20 Most Viewed #{@person_type.to_s.capitalize}"}
      @page_title = person_type == 'sen' ? "Most Viewed Senators" : "Most Viewed Representatives"
    else
      @page_title = person_type == 'sen' ? "Senators" : "Representatives"
    end

    @show_tracked_list = true
    @title_desc = SiteText.find_title_desc(person_type == 'sen' ? 'people_senator_list' : 'people_representative_list')
    #with_random_news = @people.select{|p| p.news_count.to_i > 0}.sample
    #with_random_blogs = @people.select{|p| p.blog_count.to_i > 0}.sample
    random_news, random_blogs = [[nil,nil],[nil,nil]]
    #random_news = Person.random_commentary(with_random_news.id, "news", 1, Settings.default_count_time) if with_random_news
    #random_blogs = Person.random_commentary(with_random_blogs.id, "blog", 1, Settings.default_count_time) if with_random_blogs

    @carousel = [random_news, random_blogs, @people.sort{|a,b| b.view_count.to_i <=> a.view_count.to_i}[0..9]]

    respond_to do |format|
      format.html { render :action => 'list' }
      format.js { render :action => 'update'}
    end
  end

  def compare
    @title_class = 'sort compare'
    @page_title = "Head-to-Head Vote Comparison"
    if params[:representatives]
      @peeps = Person.rep.find(:all, :order => "people.lastname ASC")
      @tab_state = "reps_tab"
    else
      @peeps = Person.sen.find(:all, :order => "people.lastname ASC")
      @tab_state = "sens_tab"
    end

    @suggestions = (0..2).map{ @peeps.sample(2) }

    if params[:person1] && params[:person2]
      @congress = Settings.default_congress
      @person1 = Person.find(params[:person1])
      @person2 = Person.find(params[:person2])
      @chamber = @person1.latest_role.chamber
      @head_title = " - #{@person1.title} #{@person1.lastname} and #{@person2.title} #{@person2.lastname}"

      @p1_voted_with_party = @person1.with_party
      @p1_voted_total = @person1.unabstained_roll_calls.count
      @p1_voted_with_party_pct = (@p1_voted_with_party.to_f / @p1_voted_total.to_f * 100).round rescue nil
      @p2_voted_with_party = @person2.with_party
      @p2_voted_total = @person2.unabstained_roll_calls.count
      @p2_voted_with_party_pct = (@p2_voted_with_party.to_f / @p2_voted_total.to_f * 100).round rescue nil

      if @person1.congresses_active.include?(@congress) && @person2.congresses_active.include?(@congress)
        @both_active = true
        @shared_committees = @person1.committees.find(:all, :include => :people, :conditions => ["people.id = ?", @person2.id])

        @shared_votes = RollCallVote.for_duo_in_congress(@person1, @person2, @congress)
        @identical_votes = @shared_votes.select do |vote1, vote2|
          vote1.vote == vote2.vote and not vote1.is_non_vote?
        end

        @voted_together = @identical_votes.count
        @voted_total = @shared_votes.count
        if @voted_total > 0
          @voted_together_pct = (@voted_together.to_f / @voted_total.to_f * 100).round
        else
          @voted_together_pct = 0
        end

        shared_rc_ids = @shared_votes.map{ |grp| grp.first[:roll_call_id] }
        @votes = RollCall.on_passage.includes(:roll_call_votes, :bill).where(:id => shared_rc_ids, 'roll_calls.where' => @chamber).order('date DESC')
        @votes = @votes.map{|v| [v, v.roll_call_votes.where(:person_id => [@person1.id, @person2.id]).group_by(&:person_id)]}
      else
        @both_active = false
        @shared_committees = []
        @shared_votes = []
        @voted_total = 0
        @voted_together = 0
        @voted_together_pct = 0
        @votes = []
      end
    end

    respond_to do |format|
      format.html {

      }
      format.xml {
         expires_in 6.hours, :public => true
      }
      format.json {
        render :json => Hash.from_xml(render_to_string(:template => "people/compare.xml.builder", :layout => false)).to_json, :layout => false
      }
    end

  end

  def most_commentary

    @days = days_from_params(params[:days])

    if params[:person_type] == 'representatives'
      person_type = 'rep'
      @person_type = :representatives
      @page_title = "Representatives Most Written About "
      bc_url = '/people/representatives'
      @atom = {
        'link' => "/people/representatives/atom/most/",
        'title' => "Top 20 Representatives Most Written About "
      }
    else
      person_type = 'sen'
      @person_type = :senators
      @page_title = "Senators Most Written About "
      bc_url = '/people/senators'
      @atom = {
        'link' => "/people/senators/atom/most/",
        'title' => "Top 20 Senators Most Written About "
      }
    end

    if params[:type] == 'news'
      @commentary_type = 'news'
      @page_title += "In The News"
      @atom['link'] += "news"
      @atom['title'] += "In the News"
    else
      @commentary_type = 'blog'
      @page_title += "On Blogs"
      @atom['link'] += "blog"
      @atom['title'] += "On Blogs"
    end

    @sort = @commentary_type
    @sortz = :"#{@person_type}_most_#{@commentary_type}"
    @show_article_count = true

    #check for fragment cache here!
    unless read_fragment("person_meta_#{@person_type}_#{@sort}_#{@days}")
      @people = Person.list_chamber(person_type, Settings.default_congress, "#{@commentary_type}_count DESC")
    end
    respond_to do |format|
      format.html { render :action => 'list' }
      format.js { render :action => 'update' }
    end
  end

  def atom_top_commentary
    if params[:person_type] == 'representatives'
      person_type = 'rep'
      person_type_atom = 'representatives'
      @xml_title = "Representatives Most Written About "
    else
      person_type = 'sen'
      person_type_atom = 'senators'
      @xml_title = "Senators Most Written About "
    end

    if params[:type] == 'news'
      commentary_type = 'news'
      @xml_title += "In The News"
    else
      commentary_type = 'blog'
      @xml_title += "On Blogs"
    end

    @self_href = { :controller => "people/#{person_type_atom}/atom/most", :action => commentary_type, :only_path => false }
    @alt_href = { :controller => "people/#{person_type_atom}/most", :action => commentary_type, :only_path => false }
    @atom_path = "/#{person_type}/most/#{commentary_type}"

    @date_method = :"entered_top_#{commentary_type}"

    @people = Person.top20_commentary(commentary_type, person_type)
    expires_in 60.minutes, :public => true

    render :action => 'top20_atom', :layout => false
  end


  def show_f
    render :action => :show
  end

  def comments
    @person = Person.find(params[:id], :include => :roles)
    congress = params[:congress] ? params[:congress] : Settings.default_congress
    respond_to do |format|
      format.html {

        @atom = {'link' => url_for(:only_path => false, :controller => 'people', :action => 'atom', :id => @person), 'title' => "Track " + @person.name}
        @hide_atom = true
        @meta_description = "OpenCongress profile of #{@person.name}"

        comment_redirect(params[:goto_comment]) and return if params[:goto_comment]

      }
    end
  end

  def show
    congress = params[:congress] ? params[:congress] : Settings.default_congress

    respond_to do |format|
     format.html {
      @abstain_rank = @person.abstain_rank

      comment_redirect(params[:goto_comment]) and return if params[:goto_comment]

      @include_vids_styles = true

      @featured_person_text = @person.featured_people.first

      @bio_summary = @person.wiki_bio_summary
      @atom = {'link' => url_for(:only_path => false, :controller => 'people', :action => 'atom', :id => @person), 'title' => "Track " + @person.name}
    @hide_atom = true
      }
     format.xml {
        render :xml => @person.to_xml(:include => [:recent_news, :recent_blogs])
     }
   end

 end

 def money
   @igs = @person.top_interest_groups(25)
   @fundraisers = @person.fundraisers.find(:all)
   respond_to do |format|
     format.html { render }
   end
 end

 def fundraisers
   @person = Person.find(params[:id])
   @page_title = "Fundraisers for #{@person.name}"
   @fundraisers = @person.fundraisers.paginate :page => params[:page]
   respond_to do |format|
     format.html { render }
   end
 end

 def wiki

    @include_wiki_styles = true

    require 'hpricot'
    require 'open-uri'
    @person = Person.find(params[:id])

    @comments = @stats_object = @user_object = @person
    @wiki_tab = true
    tabs
   @page_title_prefix = "U.S. Congress"
   @page_title = @person.title_full_name
   link = @person.wiki_url

    @atom = {'link' => url_for(:only_path => false, :controller => 'people', :action => 'atom', :id => @person), 'title' => "Track " + @person.name}
          @hide_atom = true
          @meta_description = "OpenCongress profile of #{@person.name}"

    doc = Hpricot(open(link))
    if doc
      doc.search("#siteSub").remove
      doc.search("#jump-to-nav").remove
      doc.search("pagetheme").remove
      content = (doc/"#bodyContent").inner_html.gsub(/&lt;pagetheme&gt;(.*)&lt;\/pagetheme&gt;/, '')
      render :inline => content, :layout => "application"
    end

 end

  def user_stats_ajax
    @person = Person.find(params[:id])
    @supporting_suggestions = @person.support_suggestions
    @opposing_suggestions = @person.oppose_suggestions
    render :action => 'user_stats_ajax', :layout => false
  end

  def news
    flash[:notice] = "News and blog archives have been temporarily disabled."
    redirect_to :action => 'show', :id => params[:id]
    return

    @person = Person.find(params[:id])
    @page = params[:page]
    @page = "1" unless @page

    if params[:sort] == 'toprated'
      @sort = 'toprated'
    elsif params[:sort] == 'oldest'
      @sort = 'oldest'
    else
      @sort = 'newest'
    end

    if @sort == 'toprated'
      @atom = {'link' => url_for(:only_path => false, :controller => 'people', :id => @person, :action => 'atom_topnews'), 'title' => "#{@person.name} highest rated news articles"}
    else
      @atom = {'link' => url_for(:only_path => false, :controller => 'people', :id => @person, :action => 'atom_news'), 'title' => "#{@person.name} news articles"}
    end

    ## check if cache fragment exists
    unless read_fragment("#{@person.fragment_cache_key}_news_#{@sort}_page_#{@page}")
      if @sort == 'toprated'
        @news = @person.news.paginate(:order => 'commentaries.average_rating IS NOT NULL DESC', :page => @page)
      elsif @sort == 'oldest'
        @news = @person.news.paginate(:order => 'commentaries.date ASC', :page => @page)
      else
        @news = @person.news.paginate :page => @page
      end
    end

    @page_title = "#{@person.full_name} In The News"
    @page_title +=  " (Highest Rated)" if (@sort == 'toprated')
  end

  def blogs
    flash[:notice] = "News and blog archives have been temporarily disabled."
    redirect_to :action => 'show', :id => params[:id]
    return

    @person = Person.find(params[:id])
    @page = params[:page]
    @page = "1" unless @page

    if params[:sort] == 'toprated'
      @sort = 'toprated'
    elsif params[:sort] == 'oldest'
      @sort = 'oldest'
    else
      @sort = 'newest'
    end

    if @sort == 'toprated'
      @atom = {'link' => url_for(:only_path => false, :controller => 'people', :id => @person, :action => 'atom_topblogs'), 'title' => "#{@person.name} highest rated blog articles"}
    else
      @atom = {'link' => url_for(:only_path => false, :controller => 'people', :id => @person, :action => 'atom_blogs'), 'title' => "#{@person.name} blog articles"}
    end

    ## check if cache fragment exists
    unless read_fragment("#{@person.fragment_cache_key}_blogs_#{@sort}_page_#{@page}")
      if @sort == 'toprated'
        @blogs = @person.blogs.paginate(:order => 'commentaries.average_rating IS NOT NULL DESC', :page => @page)
      elsif @sort == 'oldest'
        @blogs = @person.blogs.paginate(:order => 'commentaries.date ASC', :page => @page)
      else
        @blogs = @person.blogs.paginate :page => @page
      end
    end

    @page_title = "#{@person.full_name} In The Blogs"
    @page_title +=  " (Highest Rated)" if (@sort == 'toprated')
  end


  def news_blogs
    flash[:notice] = "News and blog archives have been temporarily disabled."
    redirect_to :action => 'show', :id => params[:id]
    return

    if params[:sort] == 'toprated'
      @sort = 'toprated'
    elsif params[:sort] == 'oldest'
      @sort = 'oldest'
    else
      @sort = 'newest'
    end

    unless read_fragment("#{@person.fragment_cache_key}_news_blogs_#{@sort}")
      if @sort == 'toprated'
        @blogs = @person.blogs.find(:all, :order => 'commentaries.average_rating IS NOT NULL DESC', :limit => 10)
        @news = @person.news.find(:all, :order => 'commentaries.average_rating IS NOT NULL DESC', :limit => 10)
      elsif @sort == 'oldest'
        @news = @person.news.find(:all, :order => 'commentaries.date ASC', :limit => 10)
        @blogs = @person.blogs.find(:all, :order => 'commentaries.date ASC', :limit => 10)
      else
        @news = @person.news.find(:all, :limit => 10)
        @blogs = @person.blogs.find(:all, :limit => 10)
      end
    end
  end

  def videos
    @include_vids_styles = true
    @person = Person.find(params[:id])
    @page_title = "Videos of #{@person.full_name}"

    @videos = @person.videos.paginate :page => params[:page]
  end

  def atom_news
    @person = Person.find(params[:id])
    @commentaries = @person.news.find(:all, :limit => 20)
    @commentary_type = 'news'
    expires_in 60.minutes, :public => true

    render :action => 'commentary_atom', :layout => false
  end

  def atom_blogs
    @person = Person.find(params[:id])
    @commentaries = @person.blogs.find(:all, :limit => 20)
    @commentary_type = 'blog'
    expires_in 60.minutes, :public => true

    render :action => 'commentary_atom', :layout => false
  end

  def atom_topnews
    @person = Person.find(params[:id])
    @commentaries = @person.news.find(:all, :conditions => "commentaries.average_rating > 5", :limit => 5)
    @commentary_type = 'topnews'
    expires_in 60.minutes, :public => true

    render :action => 'commentary_atom', :layout => false
  end

  def atom_topblogs
    @person = Person.find(params[:id])
    @commentaries = @person.blogs.find(:all, :conditions => "commentaries.average_rating > 5", :limit => 5)
    @commentary_type = 'topblog'
    expires_in 60.minutes, :public => true

    render :action => 'commentary_atom', :layout => false
  end

  def atom_featured
    @featured_people = FeaturedPerson.find(:all, :order => 'created_at DESC', :limit => 20)

    expires_in 60.minutes, :public => true
    render :action => 'featured_atom', :layout => false
  end

  def voting_history
    @person = Person.find(params[:id])
    @title_desc = SiteText.find_explain('voting_history')

    @page = params[:page].to_i
    @page = "1" unless (@page and @page != 0)

    @q = params[:q]
    unless @q.nil?
      query_stripped = prepare_tsearch_query(@q)

      @votes = RollCallVote.paginate_by_sql(
                  ["SELECT roll_call_votes.* FROM roll_call_votes, roll_calls, bills, bill_fulltext
                               WHERE bills.session=? AND
                                     bill_fulltext.fti_names @@ to_tsquery('english', ?) AND
                                     bills.id = bill_fulltext.bill_id AND
                                     bills.id = roll_calls.bill_id AND
                                     roll_calls.id = roll_call_votes.roll_call_id AND
                                     roll_call_votes.person_id = ?
                               ORDER BY bills.hot_bill_category_id, bills.lastaction DESC", Settings.default_congress, query_stripped, @person.id],
                               :per_page => 30, :page => @page)
      @page_title = "Voting History Search: #{@person.name}"
    else
      @votes = @person.votes.paginate(:page => @page)
      @page_title = "Voting History: #{@person.name}"
    end
  end

  def votes_with_party
    @chamber = params[:chamber] == 'house' ? 'house' : 'senate'
    @party = params[:party] == 'democrat' ? 'Democrat' : 'Republican'
    @party_adj = @party == 'Democrat' ? 'Democratic' : 'Republican'
    @people_names = @chamber == 'house' ? 'Representatives' : 'Senators'

    @people = Person.list_by_votes_with_party_ranking(@chamber, @party)

    @median = @people[(@people.size/2)]
  end

  def bills
    @page = params[:page].to_i
    @page = "1" unless @page

    @q = params[:q]

    unless @q.nil?
      query_stripped = prepare_tsearch_query(@q)

      @sponsored_bills = Bill.paginate_by_sql(
                  ["SELECT bills.* FROM bills, bill_fulltext
                               WHERE bills.session=? AND
                                      bill_fulltext.fti_names @@ to_tsquery('english', ?) AND
                                     bills.id = bill_fulltext.bill_id AND
                                     bills.sponsor_id = ?
                               ORDER BY bills.hot_bill_category_id, bills.lastaction DESC", Settings.default_congress, query_stripped, @person.id],
                               :per_page => 30,
                               :page => @page)

       @cosponsored_bills = Bill.paginate_by_sql(
                   ["SELECT bills.* FROM bills, bills_cosponsors, bill_fulltext
                                WHERE bills.session=? AND
                                      bill_fulltext.fti_names @@ to_tsquery('english', ?) AND
                                      bills.id = bill_fulltext.bill_id AND
                                      bills.id = bills_cosponsors.bill_id AND
                                      bills_cosponsors.person_id=?
                                ORDER BY bills.hot_bill_category_id, bills.lastaction DESC", Settings.default_congress, query_stripped, @person.id],
                                :per_page => 30,
                                :page => @page)
      @page_title = "Sponsored Bills Search #{@person.name}"
    else
      @sponsored_bills = @person.bills.paginate(:include => [:last_action],
                                                :per_page => 50,
                                                :page => @page)
      @cosponsored_bills = @person.bills_cosponsored.paginate(:include => [:last_action], :per_page => 50, :page => @page)
    end

    @search_text = "<span class='none'>Search Sponsored Bills</span>"
  end


  def atom
    @person = Person.find(params[:id], :include => :roles)

    @items = @person.recent_activity

    expires_in 60.minutes, :public => true

    render :layout => false
  end

  def atom_top20
    @people = Person.top20_viewed(params[:type])

    if (params[:type])
      case params[:type]
      when 'sen'
        @xml_title = "Top 20 Most Viewed Senators"
        @self_href = { :controller => 'people', :action => 'atom_top20', :type => 'sen', :only_path => false }
        @alt_href = { :controller => 'people', :action => 'senators', :sort => 'popular', :only_path => false }
        @atom_path = "/rep/most/viewed"
      when 'rep'
        @xml_title = "Top 20 Most Viewed Representatives"
        @self_href = { :controller => 'people', :action => 'atom_top20', :type => 'rep', :only_path => false }
        @alt_href = { :controller => 'people', :action => 'representatives', :sort => 'popular', :only_path => false }
        @atom_path = "/sen/most/viewed"
      end
    else
      @xml_title = "Top 20 Most Viewed Members of Congress"
    end
    @date_method = :entered_top_viewed

    expires_in 60.minutes, :public => true

    render :action => 'top20_atom', :layout => false
  end

  def zipcodelookup
    @page_title = "Find Your Senators and Representatives"
    @display_zip = params[:zip5]
    @display_zip += "-#{params[:zip4]}" unless params[:zip4].blank?
    @senators = @reps = []

    address = params[:address].to_s

    if address.blank? && params[:zip5].present?
      @senators, @reps = Person.find_current_congresspeople_by_zipcode(params[:zip5], params[:zip4])
    elsif address.present?
      if params[:zip5].present?
        address = "#{address}, #{@display_zip}"
      end
      @senators, @reps = Person.find_current_congresspeople_by_address(address)
    end

    unless @senators and @reps
      flash.now[:notice] = "Your search did not return any members of Congress." unless params[:zip5].nil?
    end
  end

  # Rate your approval of person
  def rate
    person = Person.find_by_id(params[:id])
    score = current_user.person_approvals.find_or_initialize_by_person_id(person.id)
    score.rating = params[:value]
    score.save
    if person.person_approvals.length > 5
      person.user_approval = person.person_approvals.average(:rating)
      person.save
    end
    logger.info params.to_yaml
    #render :text => "OK"
    render :update do |page|
      page.replace "approval-container", :partial => 'approval', :locals => {:person => person, :user_approval => score.rating}
      page.visual_effect :pulsate, "mscoretp#{person.id.to_s}"
      page.visual_effect :pulsate, "person_rating"
     end
  end

  def ranking
    @allowed_rankbys = %w[sponsored_bills cosponsored_bills sponsored_bills_passed cosponsored_bills_passed]
    @person_types = %w[Senators Representatives]

    @rankby = @allowed_rankbys.include?(params[:id]) ? params[:id] : 'sponsored_bills'
    @person_type_display = @person_types.include?(params[:person_type]) ? params[:person_type] : 'Senators'
    @person_type = @person_type_display == 'Senators' ? 'sen' : 'rep'

    @people = Person.find(:all,
                :include => [:roles, :person_stats],
                :conditions => [ "roles.role_type=? AND roles.enddate > ? AND person_stats.#{@rankby}_rank IS NOT NULL",
                                 @person_type,  Date.today ],
                :order => "person_stats.#{@rankby} DESC")
    @page_title = "#{@person_type_display} by #{@rankby.humanize.downcase}"
  end

  private

  def person_profile_shared
    if params[:id].blank?
      redirect_to :controller => 'people', :action => 'zipcodelookup'
      return
    end

    if @person = Person.find(params[:id])
      @page_title_prefix = "U.S. Congress"
      @page_title = (@person.senator? ? 'Senator ' : 'Rep. ') + @person.popular_name +
                    ", #{State.for_abbrev(@person.state) unless @person.state.blank?}"
      @page_title += " (#{@person.party[0,1]})" unless @person.party.blank?
      @meta_description = "Latest votes, sponsored bills, breaking news and blog coverage, and user community for #{@page_title} on OpenCongress"

      @sidebar_stats_object = @user_object = @comments = @topic = @person
      @page = params[:page] ||= 1
      if @person.has_wiki_link?
        @wiki_url = @person.wiki_url
      else
        #direct to create page for bill?
      end

      u_approval = current_user.person_approvals.find_by_person_id(@person.id) if logged_in?
      @user_approval = u_approval.rating if u_approval
      @user_approval = 5 if @user_approval.nil?

      @tabs = [
        ["Overview",{:action => 'show', :id => @person}],
        # ["Wiki","#{@wiki_url}"],
        ["Votes",{:action => 'voting_history', :id => @person}],
        ["Campaign Finance",{:action => 'money', :id => @person}],
        # ["News <span>(#{news_blog_count(@person.news_article_count)})</span> & Blogs <span>(#{news_blog_count(@person.blog_article_count)})</span>",{:action => 'news_blogs', :id => @person}],
        ["Videos <span>(#{number_with_delimiter(@person.videos.size)})</span>",{:action => 'videos', :id => @person}],
        # ["Comments <span>(#{@person.comments.size})</span>",{:action => 'comments', :id => @person}]
      ]
      @atom = {'link' => url_for(:only_path => false, :controller => 'people', :id => @person, :action => 'atom'), 'title' => "#{@person.popular_name} activity"}
      @bookmarking_image = @person.photo_path
    else
      render_404
    end

  end


  def can_text
    if !(logged_in? && current_user.user_role.can_manage_text)
      redirect_to admin_url
    end
  end

  def page_view
    unless params[:id].blank?
      @person = Person.find(params[:id])

      if @person
        key = "page_view_ip:Person:#{@person.id}:#{request.remote_ip}"
        unless read_fragment(key)
          @person.increment!(:page_views_count)
          @person.page_view
          write_fragment(key, "c", :expires_in => 1.hour)
        end
      end
    end
  end

end
