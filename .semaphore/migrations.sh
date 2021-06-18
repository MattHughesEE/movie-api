#!/bin/bash

S3_PUBLISH_BUCKET="semaphore-test-app"

file_version=$1
stack_name=$2

file_name=migrations-$file_version.zip

cache restore gems-$SEMAPHORE_GIT_BRANCH-$(checksum Gemfile.lock),gems-develop,gems-master
sem-version ruby 2.6.3
gem uninstall bundler --all --executables
gem install bundler --version 2.0.2 --no-document
bundle install --jobs=2 --path=vendor/bundle
sem-service start postgres
psql -U postgres -h localhost -c "CREATE USER semaphore WITH PASSWORD 'lola1799';"
psql -U postgres -h localhost -c "ALTER USER semaphore WITH SUPERUSER;"
RAILS_ENV=production bundle exec rake db:create db:structure:load
RAILS_ENV=production bundle exec rake assets:precompile

zip $file_name -9 -y -r . -x "spec/*" "tmp/*" "vendor/bundle/*" ".git/*"

aws s3 cp $file_name s3://$S3_PUBLISH_BUCKET/migrations/$file_name

parameters=`aws cloudformation describe-stacks --region us-east-1 --stack-name $stack_name | jq -r '.Stacks[].Parameters[].ParameterKey | select( . != "BundleKey")'`

echo "[" > params.json
for parameter in $parameters; do
  echo "{\"ParameterKey\": \"$parameter\", \"UsePreviousValue\": true}," >> params.json
done
echo "{\"ParameterKey\": \"BundleKey\", \"ParameterValue\": \"migrations/$file_name\"}" >> params.json
echo "]" >> params.json

aws cloudformation create-stack --region us-east-1 --stack-name $stack_name --templateURL s3://semaphore-test-app/migrations/migrations-070ca5b578a9c04b37801aae1befd43cf5f53aa5.zip --parameters file://params.json