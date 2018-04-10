require 'rubygems'
require 'rake'
require 'time'
require 'active_record/fixtures'
require 'csv'

namespace :seek do

  desc 'an alternative to the doc:seek task'
  task(:docs=>["doc:seek"])

  desc 'updates the md5sum, and makes a local cache, for existing remote assets'
  task(:cache_remote_content_blobs=>:environment) do
    resources = Sop.all
    resources |= Model.all
    resources |= DataFile.all
    resources = resources.select { |r| r.content_blob && r.content_blob.data.nil? && r.content_blob.url && !r.projects.empty? }

    resources.each do |res|
      res.cache_remote_content_blob
    end
  end

  task(:tissue_and_cell_types=>:environment) do
    revert_fixtures_identify
    TissueAndCellType.delete_all
    Fixtures.create_fixtures(File.join(Rails.root, "config/default_data"), "tissue_and_cell_types")
  end


  desc "Create rebranded default help documents"
  task :rebrand_help_docs => :environment do
    template = ERB.new File.new("config/rebrand/help_documents.erb").read, nil, "%"
    File.open("config/default_data/help/help_documents.yml", 'w') { |f| f.write template.result(binding) }
  end

  desc "The newer acts-as-taggable-on plugin is case insensitve. Older tags are case sensitive, leading to some odd behaviour. This task resolves the old tags"
  task :resolve_duplicate_tags=>:environment do
    tags=ActsAsTaggableOn::Tag.find :all
    skip_tags = []
    tags.each do |tag|
      unless skip_tags.include? tag
        matching = tags.select { |t| t.name.downcase.strip == tag.name.downcase.strip && t.id != tag.id }
        unless matching.empty?
          matching.each do |m|
            puts "#{m.name}(#{m.id}) - #{tag.name}(#{tag.id})"
            m.taggings.each do |tagging|
              unless tag.taggings.detect { |t| t.context==tagging.context && t.taggable==tagging.taggable }
                puts "Updating tagging #{tagging.id} to point to #{tag.name}:#{tag.id}"
                tagging.tag = tag
                tagging.save!
              else
                puts "Deleting duplicate tagging #{tagging.id}"
                tagging.delete
              end
            end
            m.delete
            skip_tags << m
          end
        end
      end
    end
  end

  desc "Overwrite footer layouts with generic, rebranded alternatives"
  task :rebrand_layouts do
    dir = 'config/rebrand/'
    #TODO: Change to select everything in config/rebrand/ except for help_documents.erb
    FileUtils.cp FileList["#{dir}/*"].exclude("#{dir}/help_documents.erb"), 'app/views/layouts/'
  end

  desc "Replace Sysmo specific files with rebranded alternatives"
  task :rebrand => [:rebrand_help_docs, :rebrand_layouts]

  desc "projects hierarchies only for existing Virtual Liver SEEK projects "
  task :projects_hierarchies =>:environment do
    root = Project.find_by_name "Virtual Liver"

    irreg_projects = [
        ctu = Project.find_by_name("CTUs"),
        show_case = Project.find_by_name("Show cases"),
        project_mt = Project.find_by_name("Project Management"),
        interleukin = Project.find_by_name("Interleukin-6 signalling"),
        pals = Project.find_by_name("PALs Team"),
        hepatosys = Project.find_by_name("HepatoSys")
    ].compact

    #root as parent
    reg_projects = Project.where('name REGEXP?', '^[A-Z][:]')
    (irreg_projects + reg_projects).each do |proj|
      proj.parent = root
      puts "#{proj.name} |has parent|  #{root.name}"
      proj.save!
    end

    #ctus
    sub_ctus = Project.where('name REGEXP?', '^CTU[^s]')
    sub_ctus.each do |proj|
      if ctu
        proj.parent = ctu
        puts "#{proj.name} |has parent|  #{ctu.name}"
        proj.save!
      end
    end
    #show cases
    ["Showcase HGF and Regeneration", "Showcase LPS and Inflammation", "Showcase Steatosis", "Showcase LIAM (Liver Image Analysis Based Model)"].each do |name|
      proj = Project.find_by_name name
      if proj and show_case
        proj.parent = show_case
        puts "#{proj.name} |has parent| #{show_case.name}"
        proj.save!
      else
        puts "Project #{name} or #{show_case.name} not found!"
      end
    end
    #project management
    ["Admin:Administration",
     "PtJ",
     "Virtual Liver Management Team",
     "Virtual Liver Scientific Advisory Board"].each do |name|
      proj = Project.find_by_name name
      if proj and project_mt
        proj.parent = project_mt
        puts "#{proj.name} |has parent| #{project_mt.name}"
        proj.save!
      else
        puts "Project #{name} or #{project_mt.name} not found!"
      end
    end
    #set parents for children of A-G,e.g.A,A1,A1.1
    reg_projects.each do |proj|
      init_char = proj.name[0].chr
      Project.where('name REGEXP?', "^#{init_char}[0-9][^.]").each do |sub_proj|
        if sub_proj
          sub_proj.parent = proj
          puts "#{sub_proj.name} |has parent| #{proj.name}"
          sub_proj.save!
          num = sub_proj.name[1].chr # get the second char of the name
          Project.where('name REGEXP?', "^#{init_char}[#{num}][.]").each { |sub_sub_proj|
            if sub_sub_proj
              sub_sub_proj.parent = sub_proj
              puts "#{sub_sub_proj.name} |has parent| #{sub_proj.name}"
              sub_sub_proj.save!
            end
          }
        end
      end
    end

    ######update work groups##############
    puts "update work groups,it may take some time..."
    disable_authorization_checks do
      Project.find_each do |proj|
        proj.institutions.each do |i|
          proj.parent.institutions << i unless proj.parent.nil? || proj.parent.institutions.include?(i)
        end
      end
    end

  end

  desc "Subscribes users to the items they would normally be subscribed to by default"
  #Run this after the subscriptions, and all subscribable classes have had their tables created by migrations
  #You can also run it any time you want to force everyone to subscribe to something they would be subscribed to by default
  task :create_default_subscriptions => :environment do
    Person.find_each do |p|
      set_default_subscriptions  p
      disable_authorization_checks {p.save(:validate=>false)}
    end
  end
  
  task(:repopulate_auth_lookup_tables_old => :environment) do
    AuthLookupUpdateJob.new.add_items_to_queue nil,5.seconds.from_now,1
    User.find_each do |user|
      unless AuthLookupUpdateQueue.exists?(user)
        AuthLookupUpdateJob.new.add_items_to_queue user,5.seconds.from_now,1
      end
    end
  end

  desc "Creates background jobs to rebuild all authorization lookup table for all items."
  task(:repopulate_auth_lookup_tables=>:environment) do
    Seek::Util.authorized_types.each do |type|
      type.find_each do |item|
        AuthLookupUpdateQueue.create(item: item, priority: 1) unless AuthLookupUpdateQueue.exists?(item)
      end
    end
    # 5 is an arbitrary number to take advantage of there being more than 1 worker dedicated to auth refresh
    5.times { AuthLookupUpdateJob.new.queue_job(1, 5.seconds.from_now) }
  end

  desc "Rebuilds all authorization tables for a given user - you are prompted for a user id"
  task(:repopulate_auth_lookup_for_user=>:environment) do
    puts "Please provide the user id:"
    user_id = STDIN.gets.chomp
    user = user_id=="0" ? nil : User.find(user_id)
    Seek::Util.authorized_types.each do |type|
      table_name = type.lookup_table_name
      ActiveRecord::Base.connection.execute("delete from #{table_name} where user_id = #{user_id}")
      assets = type.includes(:policy)
      c=0
      total=assets.count
      ActiveRecord::Base.transaction do
        assets.each do |asset|
          asset.update_lookup_table user
          c+=1
          puts "#{c} done out of #{total} for #{type.name}" if c%10==0
        end
      end
      count = ActiveRecord::Base.connection.select_one("select count(*) from #{table_name} where user_id = #{user_id}").values[0]
      puts "inserted #{count} records for #{type.name}"
      GC.start
    end
  end

  desc "Creates background jobs to reindex all searchable things"
  task(:reindex_all=>:environment) do
    Seek::Util.searchable_types.each do |type|
      ReindexingJob.new.add_items_to_queue type.all, 5.seconds.from_now,2
    end
  end

  desc "Initialize background jobs for sending subscription periodic emails"
  task(:send_periodic_subscription_emails=>:environment) do
    SendPeriodicEmailsJob.create_initial_jobs
  end

  desc('clears temporary files from filestore/tmp')
  task(:clear_filestore_tmp => :environment) do
    FileUtils.rm_r(Dir["#{Seek::Config.temporary_filestore_path}/*"])
  end

  desc('clears converted formats for assets, such as pdf and text for browser viewing and search indexing respectively. If cleared these will be regenerated when needed')
  task(:clear_converted_assets => :environment) do
    FileUtils.rm_r(Dir["#{Seek::Config.converted_filestore_path}/*"])
  end

  
  desc "warm authorization memcache"
  task :warm_memcache=> :environment do
    klasses = Seek::Util.persistent_classes.select { |klass| klass.reflect_on_association(:policy) }.reject { |klass| klass.name == 'Permission' || klass.name.match(/::Version$/) }
    items = klasses.map(&:all).flatten
    users = User.all.select(&:person)
    actions = Acts::Authorized::AUTHORIZATION_ACTIONS.map {|a| "can_#{a}?"}

    Rails.logger.silence do
      items.product(users).each do |i, u|
        actions.each do |a|
          i.send a, u
        end
      end
    end
  end

  desc "dump policy authorization caching"
  task :dump_policy_authorization_caching, [:filename] => :environment do |t, args|
    filename = args[:filename] ? args[:filename].to_s : 'cache_dump.yaml'

    klasses = Seek::Util.persistent_classes.select { |klass| klass.reflect_on_association(:policy) }.reject { |klass| klass.name == 'Permission' || klass.name.match(/::Version$/) }
    items = klasses.map(&:all).flatten.map(&:cache_key)
    people = User.all.map(&:person).compact.map(&:cache_key)
    actions = Acts::Authorized::AUTHORIZATION_ACTIONS.map {|action| "can_#{action}?"}
    auth_keys = people.product(actions, items).map(&:to_s)
    auth_hash = {}
    auth_keys.each_slice(150000) {|keys| auth_hash.merge! Rails.cache.read_multi(*keys)}
    puts "Printing"
    File.open(filename, 'w') do |f|
      f.print(YAML::dump(auth_hash))
    end
  end


  desc "load policy authorization caching"
  task :load_policy_authorization_caching,[:filename] => :environment do |t,args|
    filename = args[:filename] ? args[:filename].to_s : 'cache_dump.yaml'
    YAML.load(File.read(filename.to_s)).each_pair {|k,v| Rails.cache.write(k,v)}
  end

  desc("Synchronised the assay and technology types assigned to assays according to the current ontology, resolving any suggested types that have been added")
  task(:resynchronise_ontology_types=>[:environment,"tmp:create"]) do
    synchronizer = Seek::Ontologies::Synchronize.new
    synchronizer.synchronize
  end
  
  desc("Dump auth lookup tables")
  task(:dump_auth_lookup => :environment) do
    tables = Seek::Util.authorized_types.map(&:lookup_table_name)

    hashes = {}
    File.open('auth_lookup_dump.txt', 'w') do |f|
      f.write '{'
      tables.each_with_index do |table, i|
        puts "Dumping #{table} ..."
        array = ActiveRecord::Base.connection.execute("SELECT * FROM #{table}").each
        f.write "'#{table}' => "
        f.write array.inspect
        hashes[table] = array.hash
        f.write ',' unless i == (tables.length - 1)
      end
      f.write '}'
    end

    puts
    puts "Hashes:"
    puts JSON.pretty_generate(hashes).gsub(":", " =>")
    puts
    puts "Done"
  end

  task(:check_auth_lookup => :environment) do
    output = StringIO.new('')
    Seek::Util.authorized_types.each do |type|
      puts "Checking #{type.name.pluralize}"
      puts
      output.puts type.name
      users = User.all + [nil]
      type.find_each do |item|
        users.each do |user|
          user_id = user.nil? ? 0 : user.id
          ['view', 'edit', 'download', 'manage', 'delete'].each do |action|
            lookup = type.lookup_for_asset(action, user_id, item.id)
            actual = item.authorized_for_action(user, action)
            unless lookup == actual
              output.puts "  #{type.name} #{item.id} - User #{user_id}"
              output.puts "    Lookup said: #{lookup}"
              output.puts "    Expected: #{actual}"
            end
          end
        end
        print '.'
      end
      puts
    end

    output.rewind
    puts output.read
  end


  task(:benchmark_auth_lookup => :environment) do
    all_users = User.all.to_a
    all_items = Seek::Util.authorized_types.map { |t| t.all }.flatten

    puts "Refreshing auth lookup using new method..."
    new_method_start = Time.now
    Seek::Util.authorized_types.each do |type|
      puts type.name
      type.includes(policy: :permissions).find_each do |item|
        item.update_lookup_table_for_all_users
        print '.'
      end
      puts
    end
    new_method_time = Time.now - new_method_start

    puts
    puts new_method_time
    puts

    File.open('new_method_auth_lookup_dump.txt', 'w') do |f|
      dump_auth_tables_to_file(f)
    end

    puts "Refreshing auth lookup using old method..."
    old_method_start = Time.now
    Seek::Util.authorized_types.each do |type|
      puts type.name
      type.includes(policy: :permissions).find_each do |item|
        all_users.each do |user|
          item.update_lookup_table(user)
        end
        print '.'
      end
      puts
    end
    old_method_time = Time.now - old_method_start

    puts
    puts old_method_time
    puts

    File.open('old_method_auth_lookup_dump.txt', 'w') do |f|
      dump_auth_tables_to_file(f)
    end

    puts "New method took #{new_method_time} seconds"
    puts "Old method took #{old_method_time} seconds"
  end

  desc "dump the old biosamples data into YAML"
  task(:dump_old_biosamples_data => :environment) do
    filename = 'old_biosamples.yml'
    bytes = File.write(filename, Deprecated::Specimen.all.to_yaml)
    puts "#{bytes} bytes written to #{filename}"
  end

  desc "convert old biosamples data into new format"
  task :convert_old_biosamples_data, [:filename] => :environment do |t, args|
    sample_type = SampleType.find_by_title('SysMO Biosample')

    if sample_type.nil?
      raise "Couldn't find 'SysMO Biosample' sample type - maybe need to run `rake db:seed:sample_attribute_types`?"
    end

    filename = args[:filename]

    if filename
      # The following line stops the YAML loader from complaining about missing modules/classes
      [Deprecated::Sample, Deprecated::Specimen, Deprecated::SampleAsset, Deprecated::Treatment]
      puts "Loading biosamples data from file: #{filename}"
      specimens = YAML.load(File.read(filename))
    else
      puts "Loading biosamples data from database"
      specimens = Deprecated::Specimen.all
    end

    puts "Converting samples:\n"
    total = 0
    saved = 0
    errored = []
    specimens.each do |old_specimen|
      old_specimen.deprecated_samples.each do |old_sample|
        total += 1
        sample = Sample.new(sample_type: sample_type)

        converted_age = old_sample.age_at_sampling

        unless converted_age.blank?
          converted_age = converted_age.to_i
          case old_sample.age_at_sampling_unit.try(:title)
            when 'day'
              converted_age = converted_age * 60 * 60 * 24
            when 'hour'
              converted_age = converted_age * 60 * 60
            when 'minute'
              converted_age = converted_age * 60
          end
        end

        sample.data = {
          sample_id_or_name: old_sample.title,
          cell_culture_name: old_specimen.title,
          cell_culture_lab_identifier: old_specimen.lab_internal_number,
          cell_culture_start_date: old_specimen.born,
          cell_culture_growth_type: old_specimen.culture_growth_type.try(:title),
          cell_culture_comment: old_specimen.comments,
          cell_culture_provider_name: old_specimen.provider_name,
          cell_culture_provider_identifier: old_specimen.provider_id,
          cell_culture_strain: old_specimen.strain_id,
          sample_lab_identifier: old_sample.lab_internal_number,
          sampling_date: old_sample.sampling_date,
          age_at_sampling: converted_age,
          sample_provider_name: old_sample.provider_name,
          sample_provider_identifier: old_sample.provider_id,
          sample_comment: old_sample.comments,
          sample_organism_part: old_sample.organism_part == 'Not specified' ? '' : old_sample.organism_part.capitalize
        }
        sample.contributor = old_sample.contributor
        sample.policy = old_sample.policy || Policy.public_policy
        sample.project_ids = old_sample.project_ids
        sample.created_at = old_sample.created_at
        sample.updated_at = old_sample.updated_at

        if Sample.find_by_id(old_sample.id).nil?
          sample.id = old_sample.id
        end

        if sample.save
          print '.'
          saved += 1
        else
          print 'E'
          errored << sample
        end
      end
    end

    puts
    if errored.any?
      puts "Errors:"
      errored.each do |s|
        puts "Sample #{s.id}:"
        puts s.errors.full_messages.join("\n")
        puts
      end
    end

    puts "Done - (#{saved}/#{total} converted)"
  end

  desc "clear rack attack's throttling cache"
  task :clear_rack_attack_cache => :environment do
    Rack::Attack.cache.store.delete_matched("#{Rack::Attack.cache.prefix}:*")
    puts 'Done'
  end

  private

  def set_projects_parent array, parent
    array.each do |proj|
      unless proj.nil?
        proj.parent = parent
        proj.save!
      end

    end
  end
  def set_default_subscriptions person
    person.projects.each do |proj|
      person.project_subscriptions.build :project => proj
    end
  end

  def dump_auth_tables_to_file(f)
    types = Seek::Util.authorized_types
    f.write '{'
    types.each_with_index do |type, i|
      table = type.lookup_table_name
      array = ActiveRecord::Base.connection.execute("SELECT * FROM #{table}").each
      f.write "'#{table}' => [\n"
      array.sort_by! { |a| a[1] * 10000 + a[0] }.each_with_index do |a, j|
        f.write a.inspect
        f.write "," unless j == (array.length - 1)
        # Add a comment with some copy/pastable code to the end of each line to make debugging easier
        f.write " # a = #{type}.find(#{a[1]}); u = User.find(#{a[0]})"
        f.write "\n"
      end
      f.write "]"
      f.write ",\n" unless i == (types.length - 1)
    end
    f.write '}'
  end

end

