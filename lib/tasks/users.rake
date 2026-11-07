namespace :users do
  desc "Create a user: bin/rails 'users:create[email,password]' (adopts personas without an owner)"
  task :create, [ :email, :password ] => :environment do |_, args|
    user = User.create!(email_address: args[:email], password: args[:password])
    adopted = Persona.where(user_id: nil).update_all(user_id: user.id)
    puts "Created #{user.email_address}; adopted #{adopted} existing persona(s)"
  end
end
