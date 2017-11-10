# Introduction

Openshift has ways to collect performance statistics and such like on a cluster wide context. For example [origin-metrics using heapster](https://github.com/openshift/origin-metrics). You could even run cAdvisor on each cluster node (its just docker running on each node), and have prometheus scraping stats off each cAdvisor. Then there are commercial offering from the likes of Coscale and Sysdig. But what if you are deploying an app in just one project/namespace, and only have admin privs on that single project? You are probably just interested in whether the project app stack is up and running or does it have issues? Or even just want to examing logs on particular pods for errors? Performance stats can be got from the folks that administer the cluster, so you probably don't need to worry about that.

Thus I wrote a Nagios plugin to monitor pods within a project. Why Nagios? Well Nagios plugins can be used by any modern monitoring software like Sensu to Icinga2. Specifically the plugin checks pods are all running, or are they crashloopback restarting? Are the health checks passing or failing? Are they frequently restarting and hitting a restart threshold count?

Regarding logging, you might want to aggregate these on say ELK, rather than trawling them in a project? But it is possible with a plugin similar to the pod monitoring one. Our cluster admins had already aggregated all pod logging to a single ELK instances (although I am not sure how easy it is to dig out operational issues from that).

# Getting access to a project

Most access is done in openshift with non expiring oauth tokens. I have written the plugin to follow this. Thus you should create a service account for a project, and then get the token for that. We need to access the project from Jenkins to deploy new images/do environment resets, so have setup a service account to do that. This can be used for monitoring. Similar to this:

```
PROJ=$(oc project|awk '{print $3}'|sed 's/\"//g')
oc create serviceaccount jenkins
oc policy add-role-to-user edit system:serviceaccount:$PROJ:jenkins -n $PROJ
oc serviceaccounts get-token jenkins -n $PROJ

```

# Pod monitoring

This should be fairly obvious. You can test with origin, as long as you setup a service account.

```
$ ./check_oc_project.sh -h
check_oc_project.sh:
        -h - help.
        -t <token>   - service account token used for login.
        -n <project> - openshift project|namespace.
        -o <cluster-url> - openshift cluster url; eg https://127.0.0.1:8443
        -w - No. pod restarts warning threshold. default 5.
        -c - No. pod restarts critical threshold. default 10.
        -l - Remain logged in to openshift.

```

# Po disk space monitoring

Similar to the pod monitoring, we can do a `df` in each pod and check disk space. Optionally can use the `-p` arg to specify a pattern match to select certain pods (eg ^jenkins).


```
$ ./check_oc_pod_diskspace.sh -h
check_oc_pod_diskspace.sh:
	-h - help.
	-t <token>   - service account token used for login.
	-n <project> - openshift project|namespace.
	-o <cluster-url> - openshift cluster url; eg https://127.0.0.1:8443
	-w - Warning disk usage % threshold. default 70.
	-c - Critical disk usage % threshold. default 90.
	-p - Pod name pattern match. default none: all pods.
	-l - Remain logged in to openshift.
	-d - Switch on debugging.

```
