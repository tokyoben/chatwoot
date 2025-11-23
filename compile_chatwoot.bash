export RAILS_ENV=development
source /home/ubuntu/.nvm/nvm.sh
nvm use v16.20.2
bundle exec rails webpacker:compile
nvm use v18.20.8
bundle exec rake assets:precompile