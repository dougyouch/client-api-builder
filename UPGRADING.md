# Upgrading

## From 1.0 to 1.1: transports (optional)

1.1 has no breaking changes. Clients that include `ClientApiBuilder::ConnectionPools`, `ThreadConnections` or `HTTP2`
keep working as before, with the same `connection_pool`, `connection_per_thread` and `close_connections` class methods.

What's new is that how requests reach the network can be chosen per environment at boot, with
[transports](README.md#transports), instead of only in the client class. Move to them when one client class needs
different connection handling in different processes, for example a connection per request in a web server and
persistent connections in a background worker.

Before, the class decided for every process:

```ruby
class GitHubClient
  include ClientApiBuilder::Router
  include ClientApiBuilder::ThreadConnections

  base_url 'https://api.github.com'
  connection_per_thread ttl: 30
end
```

After, the class describes the API and each process picks its transport:

```ruby
class GitHubClient
  include ClientApiBuilder::Router

  base_url 'https://api.github.com'
end

# Sidekiq boot code; the web server keeps the default, a new connection per request
ClientApiBuilder.use_transport(ClientApiBuilder::Transports::ThreadLocal.new(ttl: 30), GitHubClient)
at_exit { ClientApiBuilder.close_transports }
```

You can also keep the `include` as the class's default and override it only where needed: a transport registered for
the class with `use_transport` wins over the one it includes, whether it's registered before or after the class loads.

| Include style | Transport |
|---|---|
| `include ClientApiBuilder::ConnectionPools` + `connection_pool(**settings)` | `Transports::Pooled.new(**settings)` |
| `include ClientApiBuilder::ThreadConnections` + `connection_per_thread(**settings)` | `Transports::ThreadLocal.new(**settings)` |
| `include ClientApiBuilder::HTTP2` | `Transports::HTTP2.new` |
| `include ClientApiBuilder::ConnectionPools` + `include ClientApiBuilder::HTTP2` | `Transports::HTTP2.new(fallback: Transports::Pooled.new)` |
| `MyClient.close_connections` | `transport.close`, or `ClientApiBuilder.close_transports` for all of them |

One behaviour to know: if your client overrides `with_http_connection`, the override still runs and still takes
precedence over every transport.

## From 0.11 to 1.0

1.0 has two breaking changes. Most clients need no code changes; check whether these apply to you.

| Change | Who is affected |
|---|---|
| [Ruby 3.3 or newer is required](#ruby-33-or-newer-is-required) | Apps on Ruby 3.2 |
| [Section class names are no longer singularized](#section-class-names-are-no-longer-singularized) | Apps with ActiveSupport loaded (any Rails app) that refer to a section's class by its constant name |

1.0 also requires [inheritance-helper 1.x](https://github.com/dougyouch/inheritance-helper/blob/master/UPGRADING.md).
If your own code uses inheritance-helper directly, check its upgrade guide too.

### Ruby 3.3 or newer is required

Ruby 3.2 reached end of life in March 2026. On Ruby 3.2, Bundler and RubyGems keep resolving to 0.11.0.

### Section class names are no longer singularized

Each `section` creates a router class and assigns it to a constant on the client class. The name came from
inheritance-helper, which used `String#classify` when ActiveSupport was loaded, and `classify` singularizes. 1.0
requires inheritance-helper 1.x, which builds the name the same way everywhere:

| Section | 0.11 with ActiveSupport | 0.11 without ActiveSupport | 1.0 |
|---|---|---|---|
| `section :users` | `UserNestedRouter` | `UsersNestedRouter` | `UsersNestedRouter` |
| `section :news_items` | `NewsItemNestedRouter` | `NewsItemsNestedRouter` | `NewsItemsNestedRouter` |
| `section :user` | `UserNestedRouter` | `UserNestedRouter` | `UserNestedRouter` |

**What doesn't change:** `client.users`, `MyClient.users_router` and `MyClient.section_routers` return the same
classes as before. Without ActiveSupport, nothing changes at all.

**What changes:** with ActiveSupport loaded, code that names the constant, such as `MyClient::UserNestedRouter`
for `section :users`, gets a `NameError` (uninitialized constant).

**Watch for a singular and a plural section in the same client.** On 0.11 with ActiveSupport, `section :user`
and `section :users` both became `UserNestedRouter`, and whichever was declared last replaced the other (with an
"already initialized constant" warning). On 1.0 each gets its own class:

```ruby
class MyClient
  include ClientApiBuilder::Router

  section(:user)  { route :me, '/me' }
  section(:users) { route :list_users, '/users' }
end

MyClient::UserNestedRouter   # 0.11: the :users section (declared last)   1.0: the :user section
MyClient::UsersNestedRouter  # 0.11: NameError                              1.0: the :users section
```

Code that used `UserNestedRouter` to mean the `:users` section doesn't fail on 1.0. It gets the `:user` section
instead, so check for this case.

#### Finding affected code

Search for the generated constants:

```bash
grep -rnE '[A-Za-z]+NestedRouter\b' app lib spec | grep -v 'ClientApiBuilder::NestedRouter'
```

#### Fixing it

Use the `<name>_router` class method, which is the same on every version:

```ruby
# before
MyClient::UserNestedRouter
# after
MyClient.users_router
```

If you can't change every reference at once, alias the old name to the section's class after it's defined:

```ruby
class MyClient
  include ClientApiBuilder::Router

  section(:users) { route :list_users, '/users' }

  # temporary: keeps 0.11's name working until callers use users_router
  UserNestedRouter = users_router
end
```

Don't add an alias that clashes with a section of that name. In the example above with both `:user` and
`:users`, `UserNestedRouter` already belongs to `:user`.
