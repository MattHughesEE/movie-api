#!/bin/bash

S3_PUBLISH_BUCKET="rosie-artifactory-migrations"

file_version=$1
stack_name=$2

file_name="ecom-$file_version.zip"

cache restore gems-$SEMAPHORE_GIT_BRANCH-$(checksum Gemfile.lock),gems-develop,gems-master
sem-version ruby 2.3.8
gem uninstall bundler --all --executables
gem install bundler --version 1.17.3 --no-document
bundle install --local --deployment --jobs=2 --path=vendor/bundle
cp ./config/application.yml.example ./config/application.yml
cp .semaphore/database.yml config/database.yml
sem-service start postgres 10.6
RAILS_ENV=production bundle exec rake db:create db:structure:load
RAILS_ENV=production bundle exec rake assets:precompile
cp ./config/database.yml.production ./config/database.yml

zip $file_name -9 -y -r . -x "spec/*" "tmp/*" "vendor/bundle/*" ".git/*"

aws s3 --profile sem-ci-service cp $file_name s3://$S3_PUBLISH_BUCKET/ECOM/$file_name

#Bundle Key for rosie-artifact-migrations s3 bucket
parameters=`aws cloudformation describe-stacks --profile sem-ci-service --stack-name $stack_name | jq -r '.Stacks[].Parameters[].ParameterKey | select( . != "BundleKey")'`

echo "[" > params.json
for parameter in $parameters; do
  echo "{\"ParameterKey\": \"$parameter\", \"UsePreviousValue\": true}," >> params.json
done
echo "{\"ParameterKey\": \"BundleKey\", \"ParameterValue\": \"ECOM/$file_name\"}" >> params.json
echo "]" >> params.json

aws cloudformation update-stack --profile sem-ci-service --stack-name $stack_name --use-previous-template --parameters file://params.json
