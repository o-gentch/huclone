require "test_helper"

class AuthorizationTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:one)
    @other = users(:two)
    @persona = @owner.personas.create!(name: "Owner persona")
  end

  test "anonymous user is redirected to sign in" do
    get persona_contents_path(@persona)
    assert_redirected_to new_session_path
  end

  test "owner can open own persona" do
    sign_in_as @owner
    get persona_contents_path(@persona)
    assert_response :success
  end

  test "other user gets 404 for foreign persona" do
    sign_in_as @other
    get persona_contents_path(@persona)
    assert_response :not_found
  end

  test "root redirects to own persona" do
    sign_in_as @owner
    get root_path
    assert_redirected_to persona_contents_path(@persona)
  end
end
