package controllers

import (
	"encoding/json"
	"fmt"
	"net/http"

	"github.com/RedHatInsights/clowder/controllers/cloud.redhat.com/clowderconfig"
)

func returnError(msg string) string {
	return fmt.Sprintf("{\"error\":%s}", msg)
}

type MetricsMuxSetup struct {
	path string
	fn   func() []string
	err  string
}

var apiData = []MetricsMuxSetup{{
	path: "/clowdapps/present/",
	fn:   GetPresentApps,
	err:  "could not load present apps for output",
}, {
	path: "/clowdapps/managed/",
	fn:   GetManagedApps,
	err:  "could not load managed apps for output",
}, {
	path: "/clowdenvs/present/",
	fn:   GetPresentEnvs,
	err:  "could not load present envs for output",
}, {
	path: "/clowdenvs/managed/",
	fn:   GetManagedEnvs,
	err:  "could not load managed envs for output",
},
}

func CreateAPIServer() *http.Server {
	mux := http.NewServeMux()

	mux.HandleFunc("/config/", func(w http.ResponseWriter, r *http.Request) {
		jsonString, _ := json.Marshal(clowderconfig.LoadedConfig)
		w.Header().Add(
			"Content-Type", "application/json",
		)
		if _, err := fmt.Fprintf(w, "%s", jsonString); err != nil {
			fmt.Fprint(w, returnError("could not load config for output"))
		}
	})

	for _, metricsMuxSetup := range apiData {
		mux.HandleFunc(metricsMuxSetup.path, func(w http.ResponseWriter, r *http.Request) {
			w.Header().Add(
				"Content-Type", "application/json",
			)
			jsonString, _ := json.Marshal(metricsMuxSetup.fn())
			if _, err := fmt.Fprintf(w, "%s", jsonString); err != nil {
				fmt.Fprint(w, returnError(metricsMuxSetup.err))
			}
		})
	}

	srv := http.Server{
		Addr:    "127.0.0.1:2019",
		Handler: mux,
	}
	return &srv
}
