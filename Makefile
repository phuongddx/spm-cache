.PHONY: install format test proxy.build proxy.clean

install:
	bundle install

format:
	bundle exec rubocop --auto-correct

test:
	bundle exec rspec

proxy.build:
	cd tools/spm-cache-proxy && swift build -c release

proxy.clean:
	cd tools/spm-cache-proxy && swift package clean
