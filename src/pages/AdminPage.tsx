import { useState } from 'react';
import { Plus, Package, Search } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { ProductTable } from '@/components/admin/ProductTable';
import { ProductForm } from '@/components/admin/ProductForm';
import { useProducts } from '@/context/ProductContext';
import { useSettings } from '@/context/SettingsContext';
import { Product } from '@/types/product';
import { toast } from '@/hooks/use-toast';
import { errorMessage } from '@/lib/api/client';

export default function AdminPage() {
  const { products, addProduct, updateProduct, deleteProduct } = useProducts();
  const [searchQuery, setSearchQuery] = useState('');
  const [isFormOpen, setIsFormOpen] = useState(false);
  const [editingProduct, setEditingProduct] = useState<Product | null>(null);

  const filteredProducts = searchQuery
    ? products.filter(p => 
        p.name.toLowerCase().includes(searchQuery.toLowerCase())
      )
    : products;

  const handleAddProduct = () => {
    setEditingProduct(null);
    setIsFormOpen(true);
  };

  const handleEditProduct = (product: Product) => {
    setEditingProduct(product);
    setIsFormOpen(true);
  };

  const handleDeleteProduct = async (id: string) => {
    try {
      await deleteProduct(id);
    } catch (e) {
      toast({ title: 'Could not delete product', description: errorMessage(e), variant: 'destructive' });
      return;
    }
    toast({
      title: 'Product deleted',
      description: 'The product has been removed from your inventory.',
    });
  };

  const handleFormSubmit = async (data: { name: string; price: number; stock: number; image?: string }) => {
    try {
      if (editingProduct) {
        await updateProduct(editingProduct.id, data);
      } else {
        await addProduct(data);
      }
    } catch (e) {
      // Keep the form open so nothing typed is lost.
      toast({ title: 'Could not save product', description: errorMessage(e), variant: 'destructive' });
      return;
    }
    toast({
      title: editingProduct ? 'Product updated' : 'Product added',
      description: editingProduct ? `${data.name} has been updated.` : `${data.name} has been added to your inventory.`,
    });
    setIsFormOpen(false);
    setEditingProduct(null);
  };

  const handleFormClose = () => {
    setIsFormOpen(false);
    setEditingProduct(null);
  };

  return (
    <div className="container py-8">
      {/* Header */}
      <div className="mb-8 flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div className="flex items-center gap-3">
          <div className="flex h-12 w-12 items-center justify-center rounded-2xl gradient-primary shadow-medium">
            <Package className="h-6 w-6 text-primary-foreground" />
          </div>
          <div>
            <h1 className="font-display text-3xl font-bold text-foreground">Product Management</h1>
            <p className="text-muted-foreground">
              {products.length} products in inventory
            </p>
          </div>
        </div>
        <Button onClick={handleAddProduct} size="lg" className="gradient-primary text-primary-foreground shadow-medium hover:shadow-glow transition-all">
          <Plus className="h-5 w-5" />
          Add Product
        </Button>
      </div>

      {/* Search */}
      <div className="relative mb-6">
        <Search className="absolute left-4 top-1/2 h-5 w-5 -translate-y-1/2 text-muted-foreground" />
        <Input
          placeholder="Search products..."
          value={searchQuery}
          onChange={e => setSearchQuery(e.target.value)}
          className="h-14 pl-12 text-lg rounded-2xl border-border shadow-soft focus:shadow-medium transition-shadow"
        />
      </div>

      {/* Products Table */}
      <ProductTable
        products={filteredProducts}
        onEdit={handleEditProduct}
        onDelete={handleDeleteProduct}
      />

      {/* Product Form Modal */}
      <ProductForm
        product={editingProduct}
        open={isFormOpen}
        onClose={handleFormClose}
        onSubmit={handleFormSubmit}
      />
    </div>
  );
}
