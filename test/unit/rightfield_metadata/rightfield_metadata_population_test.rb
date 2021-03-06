require 'test_helper'

# tests related to populating data file from rightfield metadata template
class RightfieldMetadataPopulationTest < ActiveSupport::TestCase
  def setup
    @user = Factory(:user)
    @person = @user.person
  end

  test 'basic metadata population' do
    User.with_current_user(@user) do
      project = Factory(:project, id: 9999)
      assert_equal 9999, project.id
      @person.add_to_project_and_institution(project, Factory(:institution))
      @person.save!

      blob = Factory(:rightfield_base_sample_template)
      data_file = DataFile.new(content_blob: blob)
      assert data_file.contains_extractable_spreadsheet?

      warnings = data_file.populate_metadata_from_template

      assert_equal 'My Title', data_file.title
      assert_equal 'My Description', data_file.description
      assert_equal [project], data_file.projects
      assert_empty data_file.assays

      assert_empty warnings
    end
  end

  test 'handles none excel blob' do
    User.with_current_user(@user) do
      blob = Factory(:txt_content_blob)
      data_file = DataFile.new(content_blob: blob)
      refute data_file.contains_extractable_spreadsheet?

      warnings = data_file.populate_metadata_from_template

      assert_nil data_file.title
      assert_nil data_file.description

      assert_empty warnings
    end
  end

  test 'handles none rightfield blob' do
    User.with_current_user(@user) do
      blob = Factory(:small_test_spreadsheet_content_blob)
      data_file = DataFile.new(content_blob: blob)
      assert data_file.contains_extractable_spreadsheet?

      warnings = data_file.populate_metadata_from_template

      assert_nil data_file.title
      assert_nil data_file.description

      assert_empty warnings
    end
  end

  test 'template with link to assay' do
    User.with_current_user(@user) do
      blob = Factory(:rightfield_base_sample_template_with_assay_link)
      data_file = DataFile.new(content_blob: blob)

      assay = Factory(:assay, id: 9999, contributor: @person)
      assert_equal 9999, assay.id

      project = Factory(:project, id: 9999)
      assert_equal 9999, project.id
      @person.add_to_project_and_institution(project, Factory(:institution))
      @person.save!

      warnings = data_file.populate_metadata_from_template

      assert_equal 'My Title', data_file.title
      assert_equal 'My Description', data_file.description
      assert_equal [project], data_file.projects
      assert_equal [assay], data_file.assays

      assert_empty warnings
    end
  end

  test 'initialise assay as blank when missing' do
    User.with_current_user(@user) do
      blob = Factory(:small_test_spreadsheet_content_blob)
      data_file = DataFile.new(content_blob: blob)
      assay, warnings = data_file.initialise_assay_from_template
      refute_nil assay
      assert_nil assay.title
      assert_nil assay.description
      assert_nil assay.assay_type_uri
      assert_nil assay.technology_type_uri
      assert_equal Assay.new.inspect, assay.inspect

      assert_empty warnings

      blob = Factory(:rightfield_base_sample_template)
      data_file = DataFile.new(content_blob: blob)
      assay, warnings = data_file.initialise_assay_from_template

      refute_nil assay
      assert_nil assay.title
      assert_nil assay.description
      assert_nil assay.assay_type_uri
      assert_nil assay.technology_type_uri
      assert_equal Assay.new.inspect, assay.inspect

      assert_empty warnings
    end
  end

  test 'initialise assay from template' do
    User.with_current_user(@user) do
      blob = Factory(:rightfield_base_sample_template_with_assay)
      data_file = DataFile.new(content_blob: blob)

      study = Factory(:study, id: 9999, contributor: @person)
      assert_equal 9999, study.id

      project = Factory(:project, id: 9999)
      assert_equal 9999, project.id
      @person.add_to_project_and_institution(project, Factory(:institution))
      @person.save!

      warnings = data_file.populate_metadata_from_template

      assert_equal 'My Title', data_file.title
      assert_equal 'My Description', data_file.description
      assert_equal [project], data_file.projects

      assay, warnings2 = data_file.initialise_assay_from_template
      warnings.merge(warnings2)
      refute_nil assay

      assert_equal 'My Assay Title', assay.title
      assert_equal 'My Assay Description', assay.description
      assert_equal 'http://jermontology.org/ontology/JERMOntology#Catabolic_response', assay.assay_type_uri
      assert_equal 'http://jermontology.org/ontology/JERMOntology#2-hybrid_system', assay.technology_type_uri
      assert_equal study, assay.study
      assert_empty assay.sops

      assert_empty warnings
    end
  end

  test 'initialise assay from template with sop' do
    User.with_current_user(@user) do
      blob = Factory(:rightfield_base_sample_template_with_assay_with_sop)
      data_file = DataFile.new(content_blob: blob)

      study = Factory(:study, id: 9999, contributor: @person)
      assert_equal 9999, study.id

      project = Factory(:project, id: 9999)
      assert_equal 9999, project.id
      @person.add_to_project_and_institution(project, Factory(:institution))
      @person.save!

      sop = Factory(:sop, id: 9999, contributor: @person)
      assert_equal 9999, sop.id

      warnings = data_file.populate_metadata_from_template

      assay, warnings2 = data_file.initialise_assay_from_template
      warnings.merge(warnings2)
      refute_nil assay

      assert_equal 'My Assay Title', assay.title
      assert_equal 'My Assay Description', assay.description
      assert_equal 'http://jermontology.org/ontology/JERMOntology#Catabolic_response', assay.assay_type_uri
      assert_equal 'http://jermontology.org/ontology/JERMOntology#2-hybrid_system', assay.technology_type_uri
      assert_equal study, assay.study

      assert_equal [sop], assay.sops
      assert_equal [sop], assay.assay_assets.collect(&:asset)

      assert_empty warnings
    end
  end

  test 'detect attempt to create duplicate assay' do
    User.with_current_user(@user) do
      blob = Factory(:rightfield_base_sample_template_with_assay)
      data_file = DataFile.new(content_blob: blob)

      study = Factory(:study, id: 9999, contributor: @person)
      assert_equal 9999, study.id

      duplicate_assay = Factory(:assay, title: 'My Assay Title', study: study, contributor: @person)

      project = Factory(:project, id: 9999)
      assert_equal 9999, project.id
      @person.add_to_project_and_institution(project, Factory(:institution))
      @person.save!

      warnings = data_file.populate_metadata_from_template

      assay, warnings2 = data_file.initialise_assay_from_template
      warnings.merge(warnings2)
      refute_nil assay

      assert_equal 'My Assay Title', assay.title
      assert_equal 'My Assay Description', assay.description
      assert_equal 'http://jermontology.org/ontology/JERMOntology#Catabolic_response', assay.assay_type_uri
      assert_equal 'http://jermontology.org/ontology/JERMOntology#2-hybrid_system', assay.technology_type_uri
      assert_equal study, assay.study

      assert_equal 1, warnings.count
      problems = []
      warnings.each { |w| problems << w.problem }
      assert_equal :duplicate_assay, problems[0]
    end
  end

  test 'assay from template without study' do
    User.with_current_user(@user) do
      blob = Factory(:rightfield_base_sample_template_with_assay_no_study)
      data_file = DataFile.new(content_blob: blob)

      project = Factory(:project, id: 9999)
      assert_equal 9999, project.id
      @person.add_to_project_and_institution(project, Factory(:institution))
      @person.save!

      assay, warnings = data_file.initialise_assay_from_template

      assert_equal 'My Assay Title', assay.title
      assert_equal 'My Assay Description', assay.description
      assert_equal 'http://jermontology.org/ontology/JERMOntology#Catabolic_response', assay.assay_type_uri
      assert_equal 'http://jermontology.org/ontology/JERMOntology#2-hybrid_system', assay.technology_type_uri
      assert_nil assay.study

      assert_equal 1, warnings.count
      problems = []
      warnings.each { |w| problems << w.problem }
      assert_equal [:no_study], problems
    end
  end

  test 'assay from template with no assay title' do
    User.with_current_user(@user) do
      # all assay metadata should be left empty. template is ignored if assay has no title

      blob = Factory(:rightfield_base_sample_template_with_assay_no_assay_title)
      data_file = DataFile.new(content_blob: blob)

      assay, warnings = data_file.initialise_assay_from_template

      assert_nil assay.title
      assert_nil assay.description
      assert_nil assay.assay_type_uri
      assert_nil assay.technology_type_uri
      assert_equal Assay.new.inspect, assay.inspect

      assert_empty warnings
    end
  end

  test 'assay from template with no df title or description' do
    User.with_current_user(@user) do
      blob = Factory(:rightfield_base_sample_template_with_assay_no_df_metadata)
      data_file = DataFile.new(content_blob: blob)

      study = Factory(:study, id: 9999, contributor: @person)
      assert_equal 9999, study.id

      project = Factory(:project, id: 9999)
      assert_equal 9999, project.id
      @person.add_to_project_and_institution(project, Factory(:institution))
      @person.save!

      warnings = data_file.populate_metadata_from_template

      assert_equal '', data_file.title
      assert_equal '', data_file.description
      assert_equal [project], data_file.projects

      assay, warnings2 = data_file.initialise_assay_from_template
      warnings.merge(warnings2)
      refute_nil assay

      assert_equal 'My Assay Title', assay.title
      assert_equal 'My Assay Description', assay.description
      assert_equal 'http://jermontology.org/ontology/JERMOntology#Catabolic_response', assay.assay_type_uri
      assert_equal 'http://jermontology.org/ontology/JERMOntology#2-hybrid_system', assay.technology_type_uri
      assert_equal study, assay.study

      assert_empty warnings
    end
  end

  test 'seekid identifier hosts dont match base_host' do
    with_config_value :site_base_host, 'http://myseek.com/' do
      User.with_current_user(@user) do
        blob = Factory(:rightfield_base_sample_template)
        data_file = DataFile.new(content_blob: blob)

        study = Factory(:study, id: 9999, contributor: @person)
        assert_equal 9999, study.id

        project = Factory(:project, id: 9999)
        assert_equal 9999, project.id
        @person.add_to_project_and_institution(project, Factory(:institution))
        @person.save!

        warnings = data_file.populate_metadata_from_template

        assert_equal 'My Title', data_file.title
        assert_equal 'My Description', data_file.description
        assert_empty data_file.projects

        assay, warnings2 = data_file.initialise_assay_from_template
        warnings.merge(warnings2)
        refute_nil assay

        problems = []
        warnings.each { |w| problems << w.problem }
        assert_equal [:id_not_match_host], problems
      end
    end
  end

  test 'not a project member' do
    User.with_current_user(@user) do
      project = Factory(:project, id: 9999)
      assert_equal 9999, project.id

      blob = Factory(:rightfield_base_sample_template)
      data_file = DataFile.new(content_blob: blob)

      warnings = data_file.populate_metadata_from_template

      assert_equal 'My Title', data_file.title
      assert_equal 'My Description', data_file.description
      assert_empty data_file.projects

      problems = []
      warnings.each { |w| problems << w.problem }
      assert_equal [:not_a_project_member], problems
    end
  end

  test 'cant be found in database' do
    User.with_current_user(@user) do
      blob = Factory(:rightfield_base_sample_template_with_assay_link)
      data_file = DataFile.new(content_blob: blob)

      project = Factory(:project, id: 9999)
      assert_equal 9999, project.id
      @person.add_to_project_and_institution(project, Factory(:institution))
      @person.save!

      warnings = data_file.populate_metadata_from_template

      assert_equal 'My Title', data_file.title
      assert_equal 'My Description', data_file.description
      assert_equal [project], data_file.projects
      assert_empty data_file.assays

      problems = []
      warnings.each { |w| problems << [w.problem, w.value, w.extra_info] }
      assert_equal [[:not_in_db, 'http://localhost:3000/assays/9999', Assay]], problems
    end
  end

  test 'no permission' do
    User.with_current_user(@user) do
      blob = Factory(:rightfield_base_sample_template_with_assay_link)
      data_file = DataFile.new(content_blob: blob)

      assay = Factory(:assay, id: 9999)
      assert_equal 9999, assay.id
      refute assay.can_edit?(@user)

      project = Factory(:project, id: 9999)
      assert_equal 9999, project.id
      @person.add_to_project_and_institution(project, Factory(:institution))
      @person.save!

      warnings = data_file.populate_metadata_from_template

      assert_equal 'My Title', data_file.title
      assert_equal 'My Description', data_file.description
      assert_equal [project], data_file.projects
      assert_empty data_file.assays

      problems = []
      warnings.each { |w| problems << [w.problem, w.value, w.extra_info] }
      assert_equal [[:no_permission, 'http://localhost:3000/assays/9999', ['edit', Assay]]], problems
    end
  end

  test 'no permission for sop' do
    User.with_current_user(@user) do
      blob = Factory(:rightfield_base_sample_template_with_assay_with_sop)
      data_file = DataFile.new(content_blob: blob)

      study = Factory(:study, id: 9999, contributor: @person)
      assert_equal 9999, study.id

      project = Factory(:project, id: 9999)
      assert_equal 9999, project.id
      @person.add_to_project_and_institution(project, Factory(:institution))
      @person.save!

      sop = Factory(:sop, id: 9999)
      assert_equal 9999, sop.id
      refute sop.can_view?(@user)

      warnings = data_file.populate_metadata_from_template

      assay, warnings2 = data_file.initialise_assay_from_template
      warnings.merge(warnings2)
      refute_nil assay

      assert_equal 'My Assay Title', assay.title
      assert_equal 'My Assay Description', assay.description
      assert_equal 'http://jermontology.org/ontology/JERMOntology#Catabolic_response', assay.assay_type_uri
      assert_equal 'http://jermontology.org/ontology/JERMOntology#2-hybrid_system', assay.technology_type_uri
      assert_equal study, assay.study

      assert_empty assay.sops

      problems = []
      warnings.each { |w| problems << [w.problem, w.value, w.extra_info] }
      assert_equal [[:no_permission, 'http://localhost:3000/sops/9999', ['view', Sop]]], problems
    end
  end
end
