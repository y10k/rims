# -*- coding: utf-8 -*-

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'rims/version'

Gem::Specification.new do |spec|
  spec.name          = "rims"
  spec.version       = RIMS::VERSION
  spec.authors       = ["TOKI Yoshinori"]
  spec.email         = ["toki@freedom.ne.jp"]
  spec.summary       = %q{RIMS is Ruby IMap Server}
  spec.description   = <<-'EOF'
    RIMS is Ruby IMap Server.
    This gem provides a complete IMAP server by itself.  The IMAP
    server can run as a daemon, mailboxes are provided and messages
    can be delivered to them.
  EOF
  spec.homepage      = "https://github.com/y10k/rims"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.required_ruby_version = '>= 2.0.0'

  spec.add_runtime_dependency "rims-rfc822", '>= 0.2.2'
  spec.add_runtime_dependency "riser", '>= 0.1.8'
  spec.add_runtime_dependency "logger-joint"
  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "test-unit"
  spec.add_development_dependency "rdoc"
end

# Local Variables:
# mode: Ruby
# indent-tabs-mode: nil
# End:
