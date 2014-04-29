require 'united_states'

module ImportAmendmentsJob

  def self.perform (options)
    if options[:bill_id]
      import_bill(options[:bill_id])
    elsif options[:congress]
      import_congress(options[:congress])
    elsif options[:feed]
      import_feed(options[:feed])
    end
  end

  def self.import_congress (cong_num)
    amdt_file_paths = Dir.glob(File.join(Settings.unitedstates_data_path,
                                         cong_num.to_s,
                                         'amendments',
                                         '**',
                                         'data.json'))
    amdt_file_paths.sort_by! { |path| [path.length, path] }
    import_files amdt_file_paths
  end

  def self.import_amendment (amendment_id)
    file_paths = resolve_file_paths([amendment_id]).map(&:second).compact
    if file_paths.first.nil?
      OCLogger.log "Unable to resolve file path for amendment #{amendment_id}"
    else
      import_files file_paths
    end
  end

  def self.import_feed (ios)
    amdt_idents = ios.readlines.map(&:strip).reject(&:empty?).compact
    resolved_idents = resolve_file_paths(amdt_idents)

    resolved_idents.select{ |i| i.second.nil? }.each do |i|
      OCLogger.log "Unable to resolve file path for '#{i.first}'"
    end

    file_paths = resolved_idents.map(&:second).compact
    import_files file_paths
  end

  private

  def self.resolve_file_paths (amendment_ids)
    # Returns a list of (amendemnt_id, file_path) pairs for each entry in amendment_ids.
    # The file_path is nil for unparseable ids or ids for which files do not exist.
    amendment_ids.map do |amdt_id|
      amdt_type, number, congress = UnitedStates::Bills.parse_amendment_ident_string(amdt_id)
      if amdt_type.nil? || number.nil? || congress.nil?
        [amdt_id, nil]
      else
        file_path = UnitedStates::Bills.amendment_file_path(congress, amdt_type, number)
        if File.exists?(file_path)
          [amdt_id, file_path]
        else
          [amdt_id, nil]
        end
      end
    end
  end

  def self.import_files (file_paths)
    file_paths.each_with_index do |file_path, idx|
      if file_paths.length > 1
        OCLogger.log "Importing amendment from #{file_path} (#{idx + 1} of #{file_paths.count})"
      else
        OCLogger.log "Importing amendment from #{file_path}"
      end
      amdt_hash = UnitedStates::Bills.parse_amendment_file(file_path)
      UnitedStates::Bills.import_amendment amdt_hash
    end
  end
end
