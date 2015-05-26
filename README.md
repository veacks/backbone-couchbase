backbone-couchbase
==================

Couchbase connector for Backbone.js (Server Side)

# Configuration

Backbone = require "backbone"

couchbaseSync = require("backbone-couchbase")(
	connection:
        connection:
          cluster: "couchbase://localhost/default"
          bucket: "testBucket"
          password: "password"
)

Backnone.sync = couchbaseSync


Work in progress, documentation comming soon.
- N1QL for collections not implemented yet
- Some unit tests are still missing (collection fetch, multiget joins)