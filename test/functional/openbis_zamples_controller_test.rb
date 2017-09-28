require 'test_helper'
require 'openbis_test_helper'

include SharingFormTestHelper

class OpenbisZamplesControllerTest < ActionController::TestCase
  include AuthenticatedTestHelper

  def setup
    mock_openbis_calls
    @project_administrator = Factory(:project_administrator)
    @project = @project_administrator.projects.first
    @user = Factory(:person)
    @user.add_to_project_and_institution(@project,@user.institutions.first)
    assert @user.save
    @endpoint = Factory(:openbis_endpoint, project: Factory(:project))
  end

  test 'setup works' do
    assert @user
    assert @project_administrator
    assert @project
    assert_includes @user.projects, @project
    assert @endpoint
  end

  test 'index gives index view' do
    login_as(@user)
    get :index, project_id: @project.id, openbis_endpoint_id: @endpoint.id

    assert_response :success
  end
end