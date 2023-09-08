package web

import (
	"fmt"
	"testing"
)

func TestCaddyConfig(_ *testing.T) {
	e, _ := GenerateConfig("host", "bop", []string{"wer"}, []ProxyRoute{{
		Upstream: "11",
		Path:     "22",
	}})
	fmt.Print(e)
}
