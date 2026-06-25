package model

import "time"

type Item struct {
	ID        int64     `gorm:"column:id;primaryKey;autoIncrement" json:"id"`
	Name      string    `gorm:"column:name;type:varchar(100);not null" json:"name"`
	Rarity    int       `gorm:"column:rarity;not null;default:1" json:"rarity"`
	Price     int       `gorm:"column:price;not null;default:0" json:"price"`
	CreatedAt time.Time `gorm:"column:created_at;autoCreateTime" json:"createdAt"`
	UpdatedAt time.Time `gorm:"column:updated_at;autoUpdateTime" json:"updatedAt"`
}

func (Item) TableName() string {
	return "items"
}
