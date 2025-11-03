package trivy
 
import data.lib.trivy
import rego.v1
 
default ignore = false
 
cve_list := {"CVE-2023-30861"}
 
ignore if input.VulnerabilityID in cve_list