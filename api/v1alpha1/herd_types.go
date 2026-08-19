/*
Copyright 2026.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
)

// EDIT THIS FILE!  THIS IS SCAFFOLDING FOR YOU TO OWN!
// NOTE: json tags are required.  Any new fields you add must have json tags for the fields to be serialized.

// HerdSpec defines the desired state of Herd
type HerdSpec struct {
	// INSERT ADDITIONAL SPEC FIELDS - desired state of cluster
	// Important: Run "make" to regenerate code after modifying this file
	// The following markers will use OpenAPI v3 schema to validate the value
	// More info: https://book.kubebuilder.io/reference/markers/crd-validation.html

	// foo is an example field of Herd. Edit herd_types.go to remove/update
	// +optional
	Foo *string `json:"foo,omitempty"`
}

// HerdStatus defines the observed state of Herd.
type HerdStatus struct {
	// INSERT ADDITIONAL STATUS FIELD - define observed state of cluster
	// Important: Run "make" to regenerate code after modifying this file

	// For Kubernetes API conventions, see:
	// https://github.com/kubernetes/community/blob/master/contributors/devel/sig-architecture/api-conventions.md#typical-status-properties

	// conditions represent the current state of the Herd resource.
	// Each condition has a unique type and reflects the status of a specific aspect of the resource.
	//
	// Standard condition types include:
	// - "Available": the resource is fully functional
	// - "Progressing": the resource is being created or updated
	// - "Degraded": the resource failed to reach or maintain its desired state
	//
	// The status of each condition is one of True, False, or Unknown.
	// +listType=map
	// +listMapKey=type
	// +optional
	Conditions []metav1.Condition `json:"conditions,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:categories=henia,shortName=hd
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=`.metadata.creationTimestamp`

// Herd is the unit of work Henia manages: a declaration naming the
// repositories to bring under management, and — through its status — the
// running instance created from that declaration.
//
// Declaration and instance are deliberately ONE object rather than two kinds.
// FR-460 says the framework "creates and configures that project's instance
// from the declaration" and FR-450 describes that instance running a loop over
// one or more repositories; read as Kubernetes those are spec and status, not
// two resources. Deployment has no DeploymentInstance. Modelling it as one
// object also dissolves FR-450's grouping question — a herd spans repositories
// by construction.
//
// The name is distinctive on purpose. `Project` collides with
// project.openshift.io, and `Repository`/`Source` sit in territory Flux and
// Knative already occupy; operators reach for `kubectl get <TAB>`, where the
// API group does not disambiguate. The cost is that `Herd` does not explain
// itself, which the categories and shortName above partly offset:
// `kubectl get henia` lists every Henia type.
type Herd struct {
	metav1.TypeMeta `json:",inline"`

	// metadata is a standard object metadata
	// +optional
	metav1.ObjectMeta `json:"metadata,omitzero"`

	// spec defines the desired state of Herd
	// +required
	Spec HerdSpec `json:"spec"`

	// status defines the observed state of Herd
	// +optional
	Status HerdStatus `json:"status,omitzero"`
}

// +kubebuilder:object:root=true

// HerdList contains a list of Herd
type HerdList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitzero"`
	Items           []Herd `json:"items"`
}

func init() {
	SchemeBuilder.Register(func(s *runtime.Scheme) error {
		s.AddKnownTypes(SchemeGroupVersion, &Herd{}, &HerdList{})
		return nil
	})
}
