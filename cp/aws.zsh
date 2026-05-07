function aws-check-session() {
  aws sts get-caller-identity
}

function aws-login() {
  aws sso login
}