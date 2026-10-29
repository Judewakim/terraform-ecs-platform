# Traffic path, tier to tier. Each hop is one ingress rule on the receiver and
# one matching egress rule on the sender, both pointing at security groups,
# not IP ranges:
#
#   internet --80/443--> ALB --8080--> app tasks --5432--> Postgres
#
# These rules live here, not in the modules, so no module depends on another's
# security group and nothing forms a cycle.

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = module.alb.security_group_id
  referenced_security_group_id = module.app.security_group_id
  description                  = "ALB to app containers"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = module.app.security_group_id
  referenced_security_group_id = module.alb.security_group_id
  description                  = "App containers from ALB only"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
}

resource "aws_vpc_security_group_egress_rule" "app_to_db" {
  security_group_id            = module.app.security_group_id
  referenced_security_group_id = module.database.security_group_id
  description                  = "App containers to Postgres"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = module.database.security_group_id
  referenced_security_group_id = module.app.security_group_id
  description                  = "Postgres from app containers only"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}
