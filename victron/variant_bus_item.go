package victron

import (
	"fmt"
	"log"
	"reflect"

	"github.com/godbus/dbus/v5"
)

type VariantBusItem struct {
	bus_item_impl
	value any
}

func NewVariantBusItem(value any) *VariantBusItem {
	return &VariantBusItem{
		value: value,
	}
}

func (f *VariantBusItem) SetValue(val dbus.Variant) (int, *dbus.Error) {
	log.Printf("%s Received %s - %v - %s", f.getObjectPath(), reflect.TypeOf(val.Value()), val.Value(), val.String())

	return -1, dbus.NewError(
		"com.victronenergy.BusItem.Error",
		[]any{"Not expected to be changed"},
	)
}

func (f *VariantBusItem) GetValue() (any, *dbus.Error) {
	return dbus.MakeVariant(f.value), nil
}

func (f *VariantBusItem) GetText() (string, *dbus.Error) {
	return fmt.Sprintf("%v", f.value), nil
}
