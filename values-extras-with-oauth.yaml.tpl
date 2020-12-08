omniauth:
  enabled: true
  autoSignInWithProvider: 
  syncProfileFromProvider: ['google_oauth2']
  syncProfileAttributes: ['email']
  allowSingleSignOn: ['google_oauth2']
  blockAutoCreatedUsers: false
  autoLinkLdapUser: true
  autoLinkSamlUser: true
  autoLinkUser: ['google_oauth2']
  externalProviders: []
  allowBypassTwoFactor: []
  providers: 
  - key: google_oauth2
    secret: gitlab-oauth-providers
